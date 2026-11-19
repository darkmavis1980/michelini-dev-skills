#!/usr/bin/env bash
# Checks the security headers on a list of paths.
#   check-headers.sh https://example.com / /admin/ /deep/link /assets/app.js @/api/health
# Prefix a path with @ to only report it (proxy or redirect locations that don't use the snippet).
set -uo pipefail
[ $# -ge 2 ] || { echo "usage: $0 <base-url> <path> [path ...]" >&2; exit 2; }
base=${1%/}; shift
want=(content-security-policy x-frame-options x-content-type-options referrer-policy strict-transport-security)
fail=0
for arg in "$@"; do
  p=${arg#@}; info=0; [ "$p" != "$arg" ] && info=1
  headers=$(curl -sS -o /dev/null -D - "$base$p" | tr -d '\r')
  status=$(echo "$headers" | head -1 | awk '{print $2}')
  missing=()
  for h in "${want[@]}"; do echo "$headers" | grep -qi "^$h:" || missing+=("$h"); done
  if [ ${#missing[@]} -eq 0 ]; then
    printf '%-40s %s  ok\n' "$p" "$status"
  else
    printf '%-40s %s  missing: %s%s\n' "$p" "$status" "${missing[*]}" "$([ $info = 1 ] && echo '  (report only)')"
    [ $info = 1 ] || fail=1
  fi
done
first=${1#@}
csp=$(curl -sS -o /dev/null -D - "$base$first" | tr -d '\r' | grep -i '^content-security-policy:' | cut -d' ' -f2-)
[ -n "$csp" ] && { echo; echo "CSP on $first:"; echo "$csp" | tr ';' '\n' | sed 's/^ */  /'; }
exit $fail
