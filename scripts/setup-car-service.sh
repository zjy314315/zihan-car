#!/usr/bin/env bash
set -euo pipefail

# Run once on the car after registering its GitHub Actions self-hosted runner.
# Optional environment variables: CAR_DEPLOY_DIR, ROS_SETUP, TCP_ROS_PORT.

REPO_DIR="${CAR_DEPLOY_DIR:-$HOME/zihan-car}"
ROS_SETUP="${ROS_SETUP:-/opt/ros/noetic/setup.bash}"
TCP_ROS_PORT="${TCP_ROS_PORT:-6001}"
RUNNER_USER="$(id -un)"
SYSTEMCTL="$(command -v systemctl)"

sudo install -d -m 0755 /etc/zihan-car
sudo tee /etc/zihan-car/bridge.env >/dev/null <<EOF
ZIHAN_CAR_DIR=$REPO_DIR
ROS_SETUP=$ROS_SETUP
TCP_ROS_PORT=$TCP_ROS_PORT
EOF

sudo install -m 0644 systemd/tcp-ros-bridge.service /etc/systemd/system/tcp-ros-bridge.service
sudo install -m 0644 systemd/voice-assistant.service /etc/systemd/system/voice-assistant.service
sudo tee /etc/sudoers.d/zihan-car-runner >/dev/null <<EOF
$RUNNER_USER ALL=(root) NOPASSWD: $SYSTEMCTL restart tcp-ros-bridge.service, $SYSTEMCTL is-active tcp-ros-bridge.service, $SYSTEMCTL restart voice-assistant.service, $SYSTEMCTL is-active voice-assistant.service, $SYSTEMCTL is-enabled voice-assistant.service
EOF
sudo chmod 0440 /etc/sudoers.d/zihan-car-runner
sudo visudo -cf /etc/sudoers.d/zihan-car-runner
sudo systemctl daemon-reload
sudo systemctl enable tcp-ros-bridge.service

echo "Car bridge configured. Enable voice-assistant.service after installing its audio and Vosk dependencies."
