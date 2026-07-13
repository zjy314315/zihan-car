#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_WORKSPACE:?This script must run from GitHub Actions.}"

DEPLOY_DIR="${CAR_DEPLOY_DIR:-$HOME/zihan-car}"
SERVICE_NAME="${CAR_BRIDGE_SERVICE:-tcp-ros-bridge.service}"
VOICE_SERVICE_NAME="${CAR_VOICE_SERVICE:-voice-assistant.service}"

mkdir -p "$DEPLOY_DIR"
rsync -a --delete \
  --exclude '.git' \
  --exclude '.github' \
  --exclude '__pycache__' \
  "$GITHUB_WORKSPACE/" "$DEPLOY_DIR/"

sudo -n systemctl restart "$SERVICE_NAME"
sudo -n systemctl is-active --quiet "$SERVICE_NAME"

if sudo -n systemctl is-enabled --quiet "$VOICE_SERVICE_NAME"; then
  sudo -n systemctl restart "$VOICE_SERVICE_NAME"
  sudo -n systemctl is-active --quiet "$VOICE_SERVICE_NAME"
fi
