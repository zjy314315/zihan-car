#!/usr/bin/env bash
set -euo pipefail

MODEL_NAME="vosk-model-small-cn-0.22"
MODEL_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/zihan-car"
MODEL_DIR="$MODEL_ROOT/$MODEL_NAME"
ARCHIVE="/tmp/$MODEL_NAME.zip"

python3 -m pip install --user -r "$(dirname "$0")/requirements.txt"

if [ ! -d "$MODEL_DIR" ]; then
  mkdir -p "$MODEL_ROOT"
  curl -fL --retry 3 -o "$ARCHIVE" "https://alphacephei.com/vosk/models/$MODEL_NAME.zip"
  python3 -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "$ARCHIVE" "$MODEL_ROOT"
  rm -f "$ARCHIVE"
fi

echo "ASR ready. Run: python3 $(dirname "$0")/recognize.py"
