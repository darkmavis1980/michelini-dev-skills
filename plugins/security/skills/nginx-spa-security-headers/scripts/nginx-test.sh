#!/usr/bin/env bash
# Runs `nginx -t` on a site config in Docker, with stub Let's Encrypt files so Certbot-managed
# configs can be checked away from the server.
#   nginx-test.sh site.conf [snippet.conf snippets/<name>.conf] ...
#   (snippet pairs: local file, path relative to /etc/nginx as used in the include)
set -euo pipefail
[ $# -ge 1 ] || { echo "usage: $0 <site.conf> [snippet-file include-path]..." >&2; exit 2; }
site=$(cd "$(dirname "$1")" && pwd)/$(basename "$1"); shift
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

mounts=(-v "$site:/etc/nginx/conf.d/default.conf:ro")
while [ $# -ge 2 ]; do
  src=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
  mounts+=(-v "$src:/etc/nginx/$2:ro"); shift 2
done

# Stub certificates for every /etc/letsencrypt/live/<name>/ the config mentions.
for name in $(grep -oE '/etc/letsencrypt/live/[^/]+' "$site" | sort -u | sed 's#.*/##'); do
  mkdir -p "$tmp/le/live/$name"
  openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj "/CN=$name" \
    -keyout "$tmp/le/live/$name/privkey.pem" -out "$tmp/le/live/$name/fullchain.pem" 2>/dev/null
done
if grep -q /etc/letsencrypt "$site"; then
  : > "$tmp/le/options-ssl-nginx.conf"
  openssl dhparam -dsaparam -out "$tmp/le/ssl-dhparams.pem" 2048 2>/dev/null
  mounts+=(-v "$tmp/le:/etc/letsencrypt:ro")
fi

# Upstream hostnames that only exist on the server (e.g. Docker service names) resolve to localhost.
hosts=()
for h in $(grep -oE 'proxy_pass https?://[a-zA-Z][a-zA-Z0-9_-]*' "$site" | sed -E 's#.*://##' | sort -u); do
  hosts+=(--add-host "$h:127.0.0.1")
done

docker run --rm ${hosts[@]+"${hosts[@]}"} "${mounts[@]}" nginx:alpine nginx -t
