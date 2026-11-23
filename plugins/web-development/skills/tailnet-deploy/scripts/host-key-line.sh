#!/usr/bin/env bash
# Prints the line to paste into the DEPLOY_SSH_KNOWN_HOSTS secret, and its fingerprint.
# Run it from any device on the tailnet (read-only: it only asks the server for its public key).
#   host-key-line.sh <DEPLOY_HOST> [ssh port]
# Then, ON THE SERVER, run:  ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
# The two fingerprints must match before you paste the line.
set -euo pipefail

host=${1:?usage: host-key-line.sh <host> [port]}
port=${2:-22}

line=$(ssh-keyscan -T 10 -t ed25519 -p "$port" "$host" 2>/dev/null | grep -v '^#' || true)
if [ -z "$line" ]; then
  echo "No ed25519 host key from $host:$port. Is this device on the tailnet, and is sshd running?" >&2
  exit 1
fi

echo "Paste this whole line into DEPLOY_SSH_KNOWN_HOSTS (not the fingerprint):"
echo
echo "$line"
echo
echo "Fingerprint to compare with the server's own:"
printf '%s\n' "$line" | ssh-keygen -lf -
