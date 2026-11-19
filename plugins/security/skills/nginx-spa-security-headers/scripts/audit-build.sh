#!/usr/bin/env bash
# Reports what a Content-Security-Policy must allow for one or more built static sites.
#   audit-build.sh dist [dist2 ...]
set -uo pipefail
[ $# -ge 1 ] || { echo "usage: $0 <dist-dir> [dist-dir ...]" >&2; exit 2; }

count() { grep -rEo "$1" --include="$2" "$3" 2>/dev/null | wc -l | tr -d ' '; }

for dir in "$@"; do
  [ -d "$dir" ] || { echo "not a directory: $dir" >&2; continue; }
  echo "=== $dir"
  echo "-- HTML"
  echo "  inline <script> blocks:      $(grep -rEo '<script(\s[^>]*)?>' --include='*.html' "$dir" | grep -vc 'src=' | tr -d ' ')"
  echo "  inline event handlers (on*=): $(count '\son[a-z]+=' '*.html' "$dir")"
  echo "  inline style attributes:     $(count '\sstyle=' '*.html' "$dir")"
  echo "-- JS (needs 'unsafe-eval' / worker-src if > 0)"
  echo "  eval(:                       $(grep -rEo '(^|[^a-zA-Z0-9_.$])eval\(' --include='*.js' "$dir" | wc -l | tr -d ' ')"
  echo "  new Function(:               $(count 'new Function\(' '*.js' "$dir")"
  echo "  Workers:                     $(count 'new (Shared)?Worker\(|importScripts\(' '*.js' "$dir")"
  echo "  injected <style> (CSS-in-JS): $(count 'createElement\(["'"'"']style["'"'"']\)|insertRule\(' '*.js' "$dir")"
  echo "-- External hosts (decide per host: real resource, or just a string such as a docs link?)"
  for ext in html css js; do
    hosts=$(grep -rEoh 'https?://[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' --include="*.$ext" "$dir" 2>/dev/null | sed -E 's#^https?://##' | sort | uniq -c | sort -rn | head -25)
    [ -n "$hosts" ] && { echo "  in *.$ext:"; echo "$hosts" | sed 's/^/    /'; }
  done
  echo "-- CSS url() targets"
  grep -rEoh 'url\([^)]*\)' --include='*.css' "$dir" 2>/dev/null | sed -E 's/url\(["'"'"']?//; s/["'"'"']?\)$//' | sed -E 's#^(https?://[^/]+).*#\1#; s#^(data:[^;,]*).*#\1#; s#^/.*/([^/]+\.)([a-z0-9]+)$#(self) *.\2#' | sort | uniq -c | sort -rn | head -15 | sed 's/^/    /'
done
