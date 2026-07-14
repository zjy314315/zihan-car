#!/usr/bin/env python3
"""Offline speech conversation using Vosk, local Ollama, and espeak-ng."""

import argparse
import json
import os
import tempfile
import subprocess
import sys
from pathlib import Path

import requests
from vosk import KaldiRecognizer, Model

SYSTEM_PROMPT = "\u4f60\u662f\u5b50\u6db5\u7684\u667a\u80fd\u5c0f\u8f66\u3002\u53ea\u7528\u4e2d\u6587\u56de\u7b54\u3002\u6bcf\u6b21\u4e0d\u8d85\u8fc7\u4e8c\u5341\u4e2a\u5b57\u3002\u4e0d\u8981\u89e3\u91ca\u3001\u7ffb\u8bd1\u6216\u4e3e\u4f8b\u3002"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", default="hw:2,0")
    parser.add_argument("--rate", type=int, default=16000)
    parser.add_argument("--model-path", type=Path, default=Path.home() / ".local/share/zihan-car/vosk-model-small-cn-0.22")
    parser.add_argument("--ollama-model", default="qwen2.5:0.5b")
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
    payload = {"model": model, "stream": False, "options": {"num_predict": 32, "temperature": 0.2}, "messages": [{"role": "system", "content": SYSTEM_PROMPT}, {"role": "user", "content": message}]}
    response = requests.post(url, json=payload, timeout=90)
    response.raise_for_status()
    reply = "".join(response.json()["message"]["content"].split())
    return reply[:20] or "\u6211\u6682\u65f6\u65e0\u6cd5\u56de\u7b54\u3002"


def speak(text: str) -> None:
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as audio:
        audio_path = audio.name
    try:
        subprocess.run(["espeak-ng", "-v", "zh", "-s", "155", "-w", audio_path, text], check=True)
        try:
            subprocess.run(["amixer", "-c", "0", "sset", "PCM", "30"], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.run(["aplay", "-D", "plughw:0,0", audio_path], check=True)
            return
        except (OSError, subprocess.CalledProcessError) as aplay_error:
            print(f"aplay playback failed, falling back to paplay: {aplay_error}", file=sys.stderr)
        environment = os.environ.copy()
        environment["XDG_RUNTIME_DIR"] = "/run/user/1000"
        environment["PULSE_SERVER"] = "unix:/run/user/1000/pulse/native"
        subprocess.run(["paplay", "--device=alsa_output.usb-C-Media_Electronics_Inc._USB_Audio_Device-00.analog-stereo", audio_path], env=environment, check=True)
    except (OSError, subprocess.CalledProcessError) as error:
        print(f"Speech playback failed: {error}", file=sys.stderr)
    finally:
        if os.path.exists(audio_path):
            os.unlink(audio_path)

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
