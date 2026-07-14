#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_WORKSPACE:?This script must run from GitHub Actions.}"

DEPLOY_DIR="${CAR_DEPLOY_DIR:-$HOME/zihan-car}"
BRIDGE_SERVICE="${CAR_BRIDGE_SERVICE:-tcp-ros-bridge.service}"
VOICE_SERVICE_NAME="${CAR_VOICE_SERVICE:-voice-assistant.service}"
CONTROL_SERVICE="${CAR_CONTROL_SERVICE:-}"
CONTROL_PORT="${CAR_CONTROL_PORT:-6000}"
DIALOG_PORT="${CAR_DIALOG_PORT:-6001}"
REQUIRE_CONTROL_PORT="${CAR_REQUIRE_CONTROL_PORT:-1}"

mkdir -p "$DEPLOY_DIR"
rsync -a --delete \
  --exclude '.git' \
  --exclude '.github' \
  --exclude '__pycache__' \
  --exclude '.codex-run-logs' \
  --exclude '.tmp-*' \
  --exclude 'zihan_car_integration/audio_files/' \
  --exclude 'zihan_car_integration/dnn_models/' \
  --exclude 'zihan_car_integration/known_faces.json' \
  --exclude 'voice_assistant/models/' \
  "$GITHUB_WORKSPACE/" "$DEPLOY_DIR/"

sudo -n install -m 0644 "$DEPLOY_DIR/systemd/tcp-ros-bridge.service" /etc/systemd/system/tcp-ros-bridge.service
sudo -n install -m 0644 "$DEPLOY_DIR/systemd/voice-assistant.service" /etc/systemd/system/voice-assistant.service
sudo -n systemctl daemon-reload

sudo -n systemctl restart "$BRIDGE_SERVICE"
sudo -n systemctl is-active "$BRIDGE_SERVICE" >/dev/null

if [ -n "$CONTROL_SERVICE" ]; then
  sudo -n systemctl restart "$CONTROL_SERVICE"
  sudo -n systemctl is-active "$CONTROL_SERVICE" >/dev/null
fi

if sudo -n systemctl is-enabled "$VOICE_SERVICE_NAME" >/dev/null; then
  sudo -n systemctl restart "$VOICE_SERVICE_NAME"
  sudo -n systemctl is-active "$VOICE_SERVICE_NAME" >/dev/null
fi

port_is_listening() {
  local port="$1"
  ss -ltn | awk 'NR > 1 { print $4 }' | grep -Eq "[:.]${port}$"
}

wait_for_port() {
  local port="$1"
  local attempts="${2:-20}"

  while [ "$attempts" -gt 0 ]; do
    if port_is_listening "$port"; then
      return 0
    fi
    attempts=$((attempts - 1))
    sleep 0.5
  done

  return 1
}

if ! wait_for_port "$DIALOG_PORT"; then
  echo "dialog port $DIALOG_PORT is not listening" >&2
  exit 1
fi

if ! wait_for_port "$CONTROL_PORT" 4; then
  message="control port $CONTROL_PORT is not listening"
  if [ "$REQUIRE_CONTROL_PORT" = "1" ]; then
    echo "$message" >&2
    exit 1
  fi
  echo "WARNING: $message" >&2
fi
