#!/usr/bin/env bash
# Deploys one commit of <app name> with Docker Compose. Runs ON THE SERVER.
# The deploy job streams it over SSH, so the server always runs the version from the commit:
#   ssh host 'bash -s -- <app_path> <sha> <host_port> <compose_project>' < scripts/deploy-compose.sh
# The server may host other apps: touch only <app_path> and the <compose_project> project.
#
# Exit codes: 64 wrong use, 65 bad input, 66 not a clone, 67 commit missing, 68 port taken,
# anything else from git / docker compose / curl.
set -euo pipefail

if [ "$#" -ne 4 ]; then
  echo "Usage: deploy-compose.sh <app_path> <sha> <host_port> <compose_project>" >&2
  exit 64
fi
app_path=$1 sha=$2 host_port=$3 project=$4

# Same rules as the "Check deploy settings" step in the workflow. Check again here, because
# this script can also be run by hand.
[[ "$app_path" =~ ^/[A-Za-z0-9._/-]+$ && "$app_path" != *..* ]] || { echo "Invalid app path: $app_path" >&2; exit 65; }
[[ "$sha" =~ ^[0-9a-f]{40}$ ]] || { echo "Invalid commit SHA: $sha" >&2; exit 65; }
if ! [[ "$host_port" =~ ^[0-9]{4,5}$ ]] || (( host_port < 1024 || host_port > 65535 )); then
  echo "Invalid host port: $host_port" >&2; exit 65
fi
[[ "$project" =~ ^[a-z0-9][a-z0-9_-]{0,62}$ ]] || { echo "Invalid compose project: $project" >&2; exit 65; }

cd "$app_path"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "$app_path is not a git clone" >&2; exit 66; }

# The job pushes the commit to refs/deploy/<environment> first; fetch only if it is still missing.
if ! git cat-file -e "$sha^{commit}" 2>/dev/null; then
  echo "Fetching $sha from origin"
  git fetch --prune origin
  git cat-file -e "$sha^{commit}" 2>/dev/null || { echo "Commit $sha not found after fetch" >&2; exit 67; }
fi

# Stop before touching anything if the port belongs to someone else: another compose
# project or container, or (where `ss` exists) a process outside Docker.
others=$(docker ps --filter "publish=$host_port" --format '{{.Label "com.docker.compose.project"}}|{{.Names}}' |
  awk -F'|' -v p="$project" '$1 != p { print $2 " (project " ($1 == "" ? "none" : $1) ")" }')
if [ -n "$others" ]; then
  echo "Port $host_port is already used by: $others" >&2
  echo "Stop it, or set another DEPLOY_HTTP_PORT." >&2
  exit 68
fi
if [ -z "$(docker ps -q --filter "publish=$host_port")" ] && command -v ss >/dev/null &&
  [ -n "$(ss -ltnH "sport = :$host_port")" ]; then
  echo "Port $host_port is already used by a process outside Docker. Set another DEPLOY_HTTP_PORT." >&2
  exit 68
fi

# Drop local edits so the build is exactly the commit. Keeps an optional untracked .env.
git reset --hard --quiet
git clean -fdx --quiet -e .env
git checkout --quiet --detach "$sha"
echo "Checked out $(git log -1 --format='%h %s')"

# compose.yaml publishes "${HOST_BIND:-0.0.0.0}:${HOST_PORT:-<local port>}:<container port>".
# All interfaces by default: a cloudflared or reverse proxy running in its own Docker
# network reaches the app through the host's LAN IP, not 127.0.0.1.
unset HOST_BIND
export HOST_PORT=$host_port
echo "Building and starting $project on port $host_port"
docker compose -p "$project" up -d --build --wait --wait-timeout 120 --remove-orphans

# The container healthcheck passed; check the published port too.
if command -v curl >/dev/null; then
  curl -fsS -o /dev/null "http://127.0.0.1:$host_port/"
else
  wget -q -O /dev/null "http://127.0.0.1:$host_port/"
fi
echo "Deployed: $(git rev-parse --short HEAD) as $project on port $host_port"
