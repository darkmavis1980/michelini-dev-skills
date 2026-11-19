#!/usr/bin/env bash
# Checks HTML/Markdown content negotiation on a site. Read-only: GET requests only.
#
# Usage: check-markdown.sh <base-url> [page-path ...]
#   check-markdown.sh http://localhost:8079 / /help
#   check-markdown.sh https://example.com / /blog/my-post
#
# For each page path it checks:
#   browser Accept, */*, no Accept      -> 200 text/html
#   text/markdown, md preferred         -> 200 text/markdown
#   text/html, text/markdown;q=0.1      -> text/html (HTML preferred)
#   a type the site can't serve         -> 406
#   <path>.md (no Accept)               -> 200 text/markdown
#   Vary: Accept on every page response (FAIL on Markdown/406, WARN on HTML: some stacks
#   add it only at the reverse proxy)
# Once per site: a missing file returns 404, not the HTML shell.
#
# Exit 0 if every check passes (warnings allowed), 1 otherwise.
set -uo pipefail

if [[ $# -lt 1 || "$1" == "-h" || "$1" == "--help" ]]; then
  sed -n 2,19p "$0" | sed 's/^# \{0,1\}//'
  exit 2
fi

BASE="${1%/}"
shift
PATHS=("$@")
[[ ${#PATHS[@]} -eq 0 ]] && PATHS=("/")

BROWSER='text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8'
fails=0
warns=0

# fetch <url> [accept|-none-]  -> sets STATUS, CTYPE, VARY
fetch() {
  local url="$1" accept="${2-}" headers
  local args=(-s -o /dev/null -D - --max-time 15)
  if [[ "$accept" == "-none-" ]]; then
    args+=(-H 'Accept:') # curl sends no Accept header at all
  elif [[ -n "$accept" ]]; then
    args+=(-H "Accept: $accept")
  fi
  headers="$(curl "${args[@]}" "$url" | tr -d '\r')"
  STATUS="$(printf '%s\n' "$headers" | awk 'toupper($1) ~ /^HTTP\// {s=$2} END {print s}')"
  CTYPE="$(printf '%s\n' "$headers" | awk -F': *' 'tolower($1)=="content-type" {print tolower($2)}' | tail -1)"
  VARY="$(printf '%s\n' "$headers" | awk -F': *' 'tolower($1)=="vary" {print tolower($2)}' | paste -sd, -)"
}

report() { # report <ok|fail|warn> <label> <detail>
  case "$1" in
    ok) printf '  ok    %-34s %s\n' "$2" "$3" ;;
    warn) printf '  WARN  %-34s %s\n' "$2" "$3"; warns=$((warns + 1)) ;;
    *) printf '  FAIL  %-34s %s\n' "$2" "$3"; fails=$((fails + 1)) ;;
  esac
}

# expect <label> <url> <accept> <status> <type-prefix|-> <vary: fail|warn|skip>
expect() {
  local label="$1" url="$2" accept="$3" want_status="$4" want_type="$5" vary_rule="$6"
  fetch "$url" "$accept"
  local got="$STATUS ${CTYPE:-no content-type}"
  if [[ "$STATUS" != "$want_status" ]] || { [[ "$want_type" != "-" ]] && [[ "$CTYPE" != "$want_type"* ]]; }; then
    report fail "$label" "got $got, want $want_status ${want_type/#-/any type}"
    return
  fi
  if [[ "$vary_rule" != "skip" && ",$VARY," != *accept* ]]; then
    report "$vary_rule" "$label" "$got, but no Vary: Accept"
    return
  fi
  report ok "$label" "$got"
}

md_twin() { # / -> /index.md, /a/b/ -> /a/b.md
  local p="${1%%\?*}"
  [[ "$p" == "/" || -z "$p" ]] && { echo "/index.md"; return; }
  p="${p%/}"
  echo "$p.md"
}

for path in "${PATHS[@]}"; do
  url="$BASE$path"
  echo "$url"
  expect "browser Accept" "$url" "$BROWSER" 200 text/html warn
  expect "Accept: */*" "$url" '*/*' 200 text/html warn
  expect "no Accept header" "$url" -none- 200 text/html warn
  expect "Accept: text/markdown" "$url" 'text/markdown' 200 text/markdown fail
  expect "markdown preferred over html" "$url" 'text/markdown, text/html;q=0.9' 200 text/markdown fail
  expect "html preferred (md q=0.1)" "$url" 'text/html, text/markdown;q=0.1' 200 text/html warn
  expect "unservable type -> 406" "$url" 'application/x-content-negotiation-probe' 406 - fail
  expect ".md twin" "$BASE$(md_twin "$path")" -none- 200 text/markdown skip
done

echo "$BASE (site-wide)"
missing="/definitely-missing-$RANDOM$RANDOM.js"
fetch "$BASE$missing" "$BROWSER"
if [[ "$STATUS" == "404" ]]; then
  report ok "missing file -> 404" "$missing"
else
  report fail "missing file -> 404" "got $STATUS ${CTYPE:-}: missing files must not get the HTML shell"
fi
fetch "$BASE/llms.txt" -none-
if [[ "$STATUS" == "200" ]]; then
  report ok "/llms.txt" "$STATUS ${CTYPE:-}"
else
  report warn "/llms.txt" "got $STATUS: consider listing the .md pages in /llms.txt"
fi

echo
echo "$fails failed, $warns warning(s)."
[[ $fails -eq 0 ]]
