#!/usr/bin/env bash
# Read-only outside-in audit of a deployed website: CDN, TLS, redirect, security headers, exposed
# files, source maps, directory listing, cookies, CORS, auth on protected paths, CDN caching.
# Only GET / HEAD / OPTIONS requests (~60). Never prints the body of an exposed file.
#
#   probe.sh https://example.com [--api /api/health] [--protected /api/admin/x]... [--extra /path]...
#            [--insecure]   accept a self-signed certificate (staging / local tests only)
#
# Output lines start with PASS / WARN / FAIL / INFO so they can be summarised.
set -uo pipefail

usage() { echo "usage: $0 <https://host[:port]> [--api <path>] [--protected <path>]... [--extra <path>]... [--insecure]" >&2; exit 2; }
[ $# -ge 1 ] || usage
BASE=${1%/}; shift
case $BASE in https://*) ;; *) echo "base URL must start with https://" >&2; exit 2 ;; esac
HOSTPORT=${BASE#https://}; HOSTPORT=${HOSTPORT%%/*}
HOST=${HOSTPORT%%:*}; PORT=443
[ "$HOST" != "$HOSTPORT" ] && PORT=${HOSTPORT##*:}
API=""; PROTECTED=(); EXTRA=(); CURL_TLS=()
while [ $# -gt 0 ]; do
  case $1 in
    --api) API=$2; shift 2 ;;
    --protected) PROTECTED+=("$2"); shift 2 ;;
    --extra) EXTRA+=("$2"); shift 2 ;;
    --insecure) CURL_TLS=(-k); shift ;;
    *) usage ;;
  esac
done

UA="deployment-audit/1.0 (read-only)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
NFAIL=0; NWARN=0
pass() { echo "PASS  $*"; }
warn() { echo "WARN  $*"; NWARN=$((NWARN + 1)); }
fail() { echo "FAIL  $*"; NFAIL=$((NFAIL + 1)); }
info() { echo "INFO  $*"; }
section() { echo; echo "## $*"; }
lower() { tr '[:upper:]' '[:lower:]'; }
hash_file() { if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
# fetch <method> <url> [extra curl args...] → headers in $TMP/h, body in $TMP/b, status in $STATUS
fetch() {
  local method=$1 url=$2; shift 2
  STATUS=$(curl -sS -m 15 -A "$UA" ${CURL_TLS[@]+"${CURL_TLS[@]}"} -X "$method" -o "$TMP/b" -D "$TMP/h" -w '%{http_code}' "$@" "$url" 2>/dev/null) || STATUS=000
  tr -d '\r' < "$TMP/h" > "$TMP/h2" && mv "$TMP/h2" "$TMP/h"
}
header() { grep -i "^$1:" "$TMP/h" | tail -1 | cut -d: -f2- | sed 's/^ *//'; }

echo "# Deployment probe: $BASE ($(date -u +%Y-%m-%dT%H:%MZ))"

# ── CDN / DNS ────────────────────────────────────────────────────────────────────────────────
section "CDN and DNS"
IPS=$(dig +short A "$HOST" 2>/dev/null | grep -E '^[0-9.]+$' | tr '\n' ' ')
IP6=$(dig +short AAAA "$HOST" 2>/dev/null | grep ':' | tr '\n' ' ')
info "A: ${IPS:-none}  AAAA: ${IP6:-none}"
fetch HEAD "$BASE/"
CDN=""
if [ -n "$(header cf-ray)" ]; then CDN=cloudflare
elif [ -n "$(header x-amz-cf-id)" ]; then CDN=cloudfront
elif [ -n "$(header x-vercel-id)" ]; then CDN=vercel
elif [ -n "$(header x-nf-request-id)" ]; then CDN=netlify
elif header x-served-by | grep -qi cache; then CDN=fastly
elif header server | grep -qi akamai; then CDN=akamai
fi
if [ "$CDN" = cloudflare ] && command -v python3 >/dev/null; then
  ranges=$(curl -s -m 10 https://www.cloudflare.com/ips-v4; echo; curl -s -m 10 https://www.cloudflare.com/ips-v6)
  in_cf=$(IPS="$IPS $IP6" RANGES="$ranges" python3 -c '
import ipaddress, os
nets = [ipaddress.ip_network(r) for r in os.environ["RANGES"].split() if r.strip()]
ips = [ipaddress.ip_address(i) for i in os.environ["IPS"].split()]
print("yes" if ips and all(any(i in n for n in nets) for i in ips) else "no")' 2>/dev/null)
  info "behind Cloudflare (cf-ray header; DNS in Cloudflare ranges: ${in_cf:-unknown})"
elif [ -n "$CDN" ]; then
  info "behind $CDN"
else
  info "no CDN detected (DNS points at the server)"
fi
[ -n "$CDN" ] && info "CDN in front: check real client IPs reach the app, the CDN-to-origin TLS mode, caching of personal data, and that the privacy policy names the CDN (see REFERENCE.md)"

# ── TLS ──────────────────────────────────────────────────────────────────────────────────────
section "TLS"
for v in tls1 tls1_1 tls1_2 tls1_3; do
  proto=$(echo | openssl s_client -connect "$HOST:$PORT" -servername "$HOST" "-$v" 2>/dev/null | grep -m1 -E '^ *Protocol *:|^New, ' | sed -E 's/.*(TLSv[0-9.]+).*/\1/')
  case $v in
    tls1|tls1_1) if echo "$proto" | grep -q TLSv; then fail "$v accepted ($proto) — disable TLS 1.0/1.1"; else pass "$v refused"; fi ;;
    tls1_2) if echo "$proto" | grep -q TLSv; then pass "TLS 1.2 offered"; else warn "TLS 1.2 not offered (some clients need it)"; fi ;;
    tls1_3) if echo "$proto" | grep -q TLSv; then pass "TLS 1.3 offered"; else warn "TLS 1.3 not offered"; fi ;;
  esac
done
cert=$(echo | openssl s_client -connect "$HOST:$PORT" -servername "$HOST" 2>/dev/null | openssl x509 -noout -subject -issuer -enddate 2>/dev/null)
if [ -n "$cert" ]; then
  end=$(echo "$cert" | sed -n 's/^notAfter=//p')
  info "certificate: $(echo "$cert" | sed -n 's/^subject=//p') · issuer: $(echo "$cert" | sed -n 's/^issuer=//p' | sed -E 's/.*CN ?= ?//') · expires $end"
  end_s=$(date -j -f "%b %e %T %Y %Z" "$end" +%s 2>/dev/null || date -d "$end" +%s 2>/dev/null || echo "")
  if [ -n "$end_s" ]; then
    days=$(( (end_s - $(date +%s)) / 86400 ))
    if [ $days -lt 0 ]; then fail "certificate expired"; elif [ $days -lt 14 ]; then warn "certificate expires in $days days"; else pass "certificate valid for $days more days"; fi
  fi
else
  fail "could not read the certificate"
fi

# ── HTTP → HTTPS ─────────────────────────────────────────────────────────────────────────────
section "HTTP to HTTPS"
if [ "$PORT" != 443 ]; then info "non-standard port $PORT: HTTP redirect not checked"; else
STATUS=$(curl -sS -m 15 -A "$UA" -o /dev/null -D "$TMP/h" -w '%{http_code}' "http://$HOST/audit-probe?q=1" 2>/dev/null) || STATUS=000
tr -d '\r' < "$TMP/h" > "$TMP/h2" && mv "$TMP/h2" "$TMP/h"
loc=$(header location)
case $STATUS in
  301|308) if [ "$loc" = "https://$HOST/audit-probe?q=1" ]; then pass "$STATUS to the same path and query on HTTPS"; else warn "$STATUS, but Location is '$loc' (expected https://$HOST/audit-probe?q=1)"; fi ;;
  302|307) warn "$STATUS (temporary) to '$loc' — use 301/308" ;;
  000) info "port 80 not reachable" ;;
  *) fail "plain HTTP answers $STATUS without redirecting to HTTPS" ;;
esac
fi

# ── Security headers ─────────────────────────────────────────────────────────────────────────
check_headers() { # <label> <path> <kind: page|api|asset>
  local label=$1 path=$2 kind=$3 missing="" v
  fetch GET "$BASE$path"
  [ "$STATUS" = 000 ] && { warn "$label ($path): no response"; return; }
  v=$(header content-security-policy)
  if [ -n "$v" ]; then
    echo "$v" | grep -q "frame-ancestors" || [ -n "$(header x-frame-options)" ] || missing="$missing frame-ancestors/X-Frame-Options"
    echo "$v" | grep -Eq "script-src[^;]*'unsafe-inline'" && warn "$label ($path): CSP allows 'unsafe-inline' scripts"
    echo "$v" | grep -Eq "script-src[^;]*'unsafe-eval'" && warn "$label ($path): CSP allows 'unsafe-eval'"
  elif [ -n "$(header content-security-policy-report-only)" ]; then
    warn "$label ($path): CSP is report-only (not enforced)"
    [ -n "$(header x-frame-options)" ] || missing="$missing X-Frame-Options"
  else
    missing="$missing Content-Security-Policy"
    [ -n "$(header x-frame-options)" ] || missing="$missing X-Frame-Options"
  fi
  [ -n "$(header x-content-type-options)" ] || missing="$missing X-Content-Type-Options"
  [ -n "$(header referrer-policy)" ] || missing="$missing Referrer-Policy"
  v=$(header strict-transport-security)
  if [ -z "$v" ]; then missing="$missing Strict-Transport-Security"
  else
    age=$(echo "$v" | sed -nE 's/.*max-age=([0-9]+).*/\1/p')
    [ -n "$age" ] && [ "$age" -lt 15552000 ] && warn "$label ($path): HSTS max-age $age is under 180 days"
  fi
  if [ -z "$missing" ]; then pass "$label ($path, $STATUS): security headers present"
  elif header cf-cache-status | grep -qi hit || header x-cache | grep -qi hit; then
    # A CDN may still hold a copy cached before the headers were added: ask the origin directly.
    local cached="$missing"; check_headers_origin=1
    fetch GET "$BASE$path?audit-nocache=$$"
    if [ -n "$(header x-content-type-options)" ] && { [ -n "$(header content-security-policy)" ] || [ -n "$(header x-frame-options)" ]; }; then
      warn "$label ($path): the CDN-cached copy lacks$cached, but the origin sends them — purge the CDN cache (or wait for the next build)"
    else
      fail "$label ($path, $STATUS): missing$cached (origin too, not just the CDN cache)"
    fi
  elif [ "$kind" = asset ]; then warn "$label ($path, $STATUS): missing$missing"
  else fail "$label ($path, $STATUS): missing$missing"; fi
  v=$(header server); echo "$v" | grep -Eq '[0-9]+\.[0-9]+' && warn "$label: Server header discloses a version ($v)"
  v=$(header x-powered-by); [ -n "$v" ] && warn "$label: X-Powered-By discloses '$v'"
  return 0
}
section "Security headers"
check_headers "home page" / page
cp "$TMP/b" "$TMP/home.html"
check_headers "deep link (SPA fallback)" /audit-probe/deep/link page
cp "$TMP/b" "$TMP/fallback.html"
ASSET=$(grep -Eo '<script[^>]+src="[^"]+"' "$TMP/home.html" | sed -E 's/.*src="([^"]+)".*/\1/' | grep -v '^https\?://' | head -1)
[ -n "$ASSET" ] && check_headers "main script" "$ASSET" asset
[ -n "$API" ] && check_headers "API" "$API" api

# ── Exposed files ────────────────────────────────────────────────────────────────────────────
section "Exposed files"
HOME_HASH=$(hash_file "$TMP/home.html"); FALLBACK_HASH=$(hash_file "$TMP/fallback.html")
PATHS=(/.git/HEAD /.git/config /.env /.env.local /.env.production /.DS_Store /package.json /package-lock.json
  /composer.json /docker-compose.yml /Dockerfile /ecosystem.config.js /ecosystem.config.cjs /.htaccess /nginx.conf
  /server-status /phpinfo.php /backup.sql /dump.sql /db.sql /.svn/entries /.vscode/settings.json /.npmrc /id_rsa)
[ ${#EXTRA[@]} -gt 0 ] && PATHS+=("${EXTRA[@]}")
exposed=0
for p in "${PATHS[@]}"; do
  fetch GET "$BASE$p"
  case $STATUS in
    200)
      h=$(hash_file "$TMP/b")
      if [ "$h" = "$FALLBACK_HASH" ] || [ "$h" = "$HOME_HASH" ]; then continue; fi   # SPA fallback page
      if grep -qi '<html' "$TMP/b" && ! grep -Eqi 'Index of|phpinfo|server-status|Apache Server Status' "$TMP/b"; then continue; fi
      # Describe without printing content.
      what="$(wc -c < "$TMP/b" | tr -d ' ') bytes, $(header content-type)"
      head -c 200 "$TMP/b" | grep -q '^ref: ' && what="$what — looks like a git HEAD"
      grep -Eq '^[A-Z_][A-Z0-9_]*=' "$TMP/b" && what="$what — looks like env variables"
      fail "$p is served ($what). Content not shown."; exposed=1 ;;
  esac
done
[ $exposed = 0 ] && pass "none of ${#PATHS[@]} sensitive paths served (404/403 or the SPA fallback page)"

# Source maps and directory listing
fetch GET "$BASE/audit-probe-$$.map"; NOMAP=$STATUS
if [ -n "$ASSET" ]; then
  fetch GET "$BASE$ASSET"; grep -q 'sourceMappingURL=' "$TMP/b" && warn "main script references a source map (sourceMappingURL)"
  fetch GET "$BASE$ASSET.map"
  if [ "$STATUS" = 200 ] && grep -q '"mappings"' "$TMP/b"; then warn "source map served: $ASSET.map (exposes original source)"; else pass "no source map for $ASSET"; fi
  dir=$(dirname "$ASSET")/
  fetch GET "$BASE$dir"
  if grep -Eqi '<title>Index of|Directory listing' "$TMP/b"; then fail "directory listing enabled at $dir"; else pass "no directory listing at $dir ($STATUS)"; fi
fi

# ── Cookies ──────────────────────────────────────────────────────────────────────────────────
section "Cookies"
seen=0
for p in / ${API:+"$API"}; do
  fetch GET "$BASE$p"
  grep -i '^set-cookie:' "$TMP/h" | cut -d: -f2- | while read -r c; do
    name=${c%%=*}; flags=$(echo "$c" | lower); miss=""
    echo "$flags" | grep -q '; *secure' || miss="$miss Secure"
    echo "$flags" | grep -q '; *httponly' || miss="$miss HttpOnly"
    echo "$flags" | grep -q '; *samesite' || miss="$miss SameSite"
    if [ -z "$miss" ]; then echo "PASS  cookie '$name' on $p: Secure, HttpOnly, SameSite"; else echo "WARN  cookie '$name' on $p: missing$miss (fine only if JavaScript must read it)"; fi
  done
  grep -qi '^set-cookie:' "$TMP/h" && seen=1
done
[ $seen = 0 ] && info "no cookies set without signing in (sign-in cookies can't be checked from outside; check them in the code)"

# ── CORS ─────────────────────────────────────────────────────────────────────────────────────
if [ -n "$API" ]; then
  section "CORS on the API"
  fetch GET "$BASE$API" -H "Origin: https://audit-probe.invalid"
  acao=$(header access-control-allow-origin); acac=$(header access-control-allow-credentials | lower)
  if [ "$acao" = "https://audit-probe.invalid" ] && [ "$acac" = true ]; then fail "API reflects any Origin with credentials allowed — any site can read signed-in responses"
  elif [ "$acao" = "https://audit-probe.invalid" ]; then warn "API reflects any Origin (no credentials)"
  elif [ "$acao" = "*" ]; then info "API allows any origin without credentials (fine for public data only)"
  else pass "API doesn't grant CORS to a foreign origin"; fi
fi

# ── Protected paths and caching ──────────────────────────────────────────────────────────────
if [ ${#PROTECTED[@]} -gt 0 ]; then
  section "Protected paths (no session)"
  for p in "${PROTECTED[@]}"; do
    fetch GET "$BASE$p"
    case $STATUS in
      401|403) pass "$p → $STATUS" ;;
      301|302|303|307|308) info "$p → $STATUS to $(header location) (check it's a sign-in page)" ;;
      200) fail "$p → 200 without a session" ;;
      *) warn "$p → $STATUS" ;;
    esac
    cc=$(header cache-control | lower); cdn=$(header cf-cache-status)$(header x-cache)
    echo "$cdn" | grep -qi hit && fail "$p was served from the CDN cache ($cdn)"
    echo "$cc" | grep -q public && warn "$p sends Cache-Control: $cc"
  done
fi
if [ -n "$API" ]; then
  fetch GET "$BASE$API"; cdn=$(header cf-cache-status)$(header x-cache)
  echo "$cdn" | grep -qi hit && warn "API response came from the CDN cache ($cdn) — make sure no personal data is cached"
fi

# ── Methods ──────────────────────────────────────────────────────────────────────────────────
section "HTTP methods"
fetch OPTIONS "$BASE/"
allow=$(header allow)
[ -n "$allow" ] && info "OPTIONS / → Allow: $allow"
echo "$allow" | grep -qi trace && warn "TRACE advertised"
pass "probe used GET/HEAD/OPTIONS only"

echo
echo "# Summary: $NFAIL fail, $NWARN warn (see REFERENCE.md for what each means and how to fix it)"
exit 0
