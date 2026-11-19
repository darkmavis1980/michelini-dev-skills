#!/usr/bin/env bash
# Deploys the commit that is checked out. release.yml checks out the release tag first
# (detached HEAD). Run by hand on a branch, it fast-forwards that branch first.
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$APP_DIR"

if git symbolic-ref -q HEAD >/dev/null; then
  echo "On branch $(git branch --show-current): pulling"
  git pull --ff-only
else
  echo "Deploying $(git describe --tags --always)"
fi

echo "Installing dependencies (lockfile only)"
# --include=dev: build tools (vite, tsx) are devDependencies, and a NODE_ENV=production shell would skip them.
npm ci --include=dev

echo "Building static apps"
# One line per app nginx serves, or `npm run build` if the root script builds them all.
npm run build --workspace apps/client
npm run build --workspace apps/admin

echo "Running migrations (old server still serving)"
# Migrations must work with the old code too: if this fails, set -e stops here and the
# old version keeps running.
npm run migrate:up --workspace apps/server

echo "Starting or reloading PM2 apps"
pm2 startOrReload ecosystem.config.js --update-env
pm2 save

echo "Done: $(git describe --tags --always)"
