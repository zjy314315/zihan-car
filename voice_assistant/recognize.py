#!/usr/bin/env python3
"""Continuously transcribe Chinese speech from an ALSA microphone."""

import argparse
import json
import signal
import subprocess
import sys
from pathlib import Path

from vosk import KaldiRecognizer, Model


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", default="hw:2,0", help="ALSA capture device")
    parser.add_argument("--rate", type=int, default=16000, help="Sample rate in Hz")
    parser.add_argument(
        "--model",
        type=Path,
        default=Path.home() / ".local" / "share" / "zihan-car" / "vosk-model-small-cn-0.22",
        help="Path to the extracted Vosk Chinese model",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not args.model.is_dir():
        print(f"Vosk model not found: {args.model}", file=sys.stderr)
        return 2

    recorder = subprocess.Popen(
        [
            "arecord",
            "-D",
            args.device,
            "-f",
            "S16_LE",
            "-r",
            str(args.rate),
            "-c",
            "1",
            "-t",
            "raw",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    recognizer = KaldiRecognizer(Model(str(args.model)), args.rate)

    def stop(_signum: int, _frame: object) -> None:
        recorder.terminate()

    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)

    try:
        assert recorder.stdout is not None
        while data := recorder.stdout.read(4000):
            if recognizer.AcceptWaveform(data):
                text = json.loads(recognizer.Result()).get("text", "").strip()
                if text:
                    print(text, flush=True)
    finally:
        if recorder.poll() is None:
            recorder.terminate()
            recorder.wait(timeout=5)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
