# Offline Chinese Speech Recognition

The recognizer uses the XFM-DP USB microphone array (`hw:2,0`) and the local
Vosk small Chinese model. It outputs each final recognized phrase to stdout.

```bash
cd voice_assistant
chmod +x setup_asr.sh recognize.py
./setup_asr.sh
python3 recognize.py
```

Use `Ctrl+C` to stop recognition. A different ALSA device can be selected with
`--device`, for example `python3 recognize.py --device hw:1,0`.
