#!/usr/bin/env python3
"""Offline speech conversation using Vosk, local Ollama, and espeak-ng."""

import argparse
import json
import subprocess
import sys
from pathlib import Path

import requests
from vosk import KaldiRecognizer, Model

SYSTEM_PROMPT = "?????????????????????????,????????????????????????"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", default="hw:2,0")
    parser.add_argument("--rate", type=int, default=16000)
    parser.add_argument("--model-path", type=Path, default=Path.home() / ".local/share/zihan-car/vosk-model-small-cn-0.22")
    parser.add_argument("--ollama-model", default="tinyllama:latest")
    parser.add_argument("--ollama-url", default="http://127.0.0.1:11434/api/chat")
    return parser.parse_args()


class Listener:
    def __init__(self, model: Model, device: str, rate: int) -> None:
        self.model, self.device, self.rate = model, device, rate
        self.recorder = None
        self.recognizer = None
        self.reset()

    def reset(self) -> None:
        if self.recorder and self.recorder.poll() is None:
            self.recorder.terminate()
            try:
                self.recorder.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self.recorder.kill()
                self.recorder.wait()
        self.recorder = subprocess.Popen(["arecord", "-D", self.device, "-f", "S16_LE", "-r", str(self.rate), "-c", "1", "-t", "raw"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        self.recognizer = KaldiRecognizer(self.model, self.rate)

    def next_phrase(self) -> str:
        assert self.recorder and self.recorder.stdout and self.recognizer
        while data := self.recorder.stdout.read(4000):
            if self.recognizer.AcceptWaveform(data):
                return json.loads(self.recognizer.Result()).get("text", "").strip()
        raise RuntimeError("Microphone capture stopped")


def fixed_reply(message: str) -> str:
    normalized = "".join(message.split())
    if "\u4f60\u597d" in normalized or normalized in {"\u60a8\u597d", "\u5c0f\u8f66\u4f60\u597d", "\u5462"}:
        return "\u4f60\u597d\uff0c\u6211\u662f\u5c0f\u8f66\u3002"
    return ""

def ask_ollama(url: str, model: str, message: str) -> str:
    payload = {"model": model, "stream": False, "options": {"num_predict": 40, "temperature": 0.2}, "messages": [{"role": "system", "content": SYSTEM_PROMPT}, {"role": "user", "content": message}]}
    response = requests.post(url, json=payload, timeout=90)
    response.raise_for_status()
    return response.json()["message"]["content"].strip()


def speak(text: str, device: str = "plughw:0,0") -> None:
    speaker = subprocess.Popen(["espeak-ng", "-v", "zh", "-s", "155", "--stdout", text], stdout=subprocess.PIPE)
    assert speaker.stdout is not None
    player = subprocess.Popen(["aplay", "-q", "-D", device], stdin=speaker.stdout)
    speaker.stdout.close()
    player.wait()
    speaker.wait()


def main() -> int:
    args = parse_args()
    if not args.model_path.is_dir():
        print(f"Vosk model not found: {args.model_path}", file=sys.stderr)
        return 2
    listener = Listener(Model(str(args.model_path)), args.device, args.rate)
    print("Voice assistant ready. Say '????' to stop.", flush=True)
    try:
        while True:
            phrase = listener.next_phrase()
            if not phrase:
                continue
            print(f"You: {phrase}", flush=True)
            if phrase in {"????", "????", "????"}:
                speak("??,???")
                return 0
            try:
                answer = fixed_reply(phrase) or ask_ollama(args.ollama_url, args.ollama_model, phrase)
            except requests.RequestException as error:
                answer = "?????????????"
                print(f"Ollama request failed: {error}", file=sys.stderr)
            print(f"Car: {answer}", flush=True)
            listener.reset()
            speak(answer)
            listener.reset()
    finally:
        if listener.recorder and listener.recorder.poll() is None:
            listener.recorder.terminate()


if __name__ == "__main__":
    raise SystemExit(main())
