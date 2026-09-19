#!/usr/bin/env bash
# Prepare this host so the podcd agent can reconcile it against this
# repository. Idempotent: safe to re-run after any change.
#
#   ./bootstrap/bootstrap.sh [--repo-url URL] [--revision REV] [--host NAME]
#
# Defaults point the agent at this checkout as a local Git remote, so the
# agent reconciles the committed state of this directory. Working-tree edits
# do nothing until they are committed - that is the GitOps contract, not a
# limitation.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_URL="$REPO_ROOT"
REVISION=""
HOST_NAME="workstation"
NETWORK="ai"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-url)  REPO_URL="$2";  shift 2 ;;
    --revision)  REVISION="$2";  shift 2 ;;
    --host)      HOST_NAME="$2"; shift 2 ;;
    --network)   NETWORK="$2";   shift 2 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$REVISION" ]]; then
  REVISION="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
fi

command -v podcd >/dev/null || { echo "podcd not on PATH" >&2; exit 1; }
command -v podman >/dev/null || { echo "podman not on PATH" >&2; exit 1; }

# podcd writes Network= into the Quadlet units but does not create networks.
# Without this the three pods cannot resolve each other by name.
if ! podman network exists "$NETWORK" 2>/dev/null; then
  echo "creating podman network $NETWORK"
  podman network create "$NETWORK" >/dev/null
fi

# Services must survive logout, or the agent stops with the login session.
if [[ "$(loginctl show-user "$USER" -p Linger --value 2>/dev/null)" != "yes" ]]; then
  echo "enabling lingering for $USER (needs sudo)"
  sudo loginctl enable-linger "$USER"
fi

ENV_FILE="$HOME/.config/podcd/agent.env"
mkdir -p "$(dirname "$ENV_FILE")"
touch "$ENV_FILE"
chmod 600 "$ENV_FILE"

# litellm refuses to start without a master key, and Open WebUI uses the
# same value as its client key. Generated once, then left alone.
if ! grep -q '^LITELLM_MASTER_KEY=' "$ENV_FILE"; then
  echo "generating LITELLM_MASTER_KEY in $ENV_FILE"
  printf 'LITELLM_MASTER_KEY=sk-%s\n' "$(openssl rand -hex 24)" >> "$ENV_FILE"
fi

echo "pointing the agent at $REPO_URL ($REVISION) as host $HOST_NAME"
podcd config create --host "$HOST_NAME" --repo-url "$REPO_URL" --revision "$REVISION"
podcd install

systemctl --user daemon-reload
systemctl --user enable --now podcd-agent.service

echo
echo "done. the agent reconciles every minute."
echo "  podcd status"
echo "  podcd logs"
echo
grep '^LITELLM_MASTER_KEY=' "$ENV_FILE"
