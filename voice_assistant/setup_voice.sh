#!/usr/bin/env bash
set -euo pipefail

sudo apt-get update
sudo apt-get install -y espeak-ng
"$(dirname "$0")/setup_asr.sh"
