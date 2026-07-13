#!/usr/bin/env python3
"""
车载音频播放服务
运行在小车 Jetson 上，端口 5002
接收 App 音乐播放器的请求，通过扬声器播放音频文件

启动: python3 audio_server.py
"""

import os
import sys
import json
import glob
import subprocess
import threading
import time
from typing import Optional
from flask import Flask, jsonify, request, send_from_directory

app = Flask(__name__)
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
AUDIO_DIR = os.path.join(SCRIPT_DIR, "audio_files")
DEFAULT_VOLUME = 70

os.makedirs(AUDIO_DIR, exist_ok=True)

# 播放状态
play_lock = threading.Lock()
current_process: Optional[subprocess.Popen] = None
current_volume = DEFAULT_VOLUME
is_playing = False


def get_audio_files():
    """扫描音频目录，返回文件列表"""
    files = []
    for ext in ["*.mp3", "*.wav", "*.ogg", "*.flac", "*.m4a"]:
        for path in sorted(glob.glob(os.path.join(AUDIO_DIR, ext))):
            name = os.path.basename(path)
            size_kb = round(os.path.getsize(path) / 1024, 1)
            files.append({"name": name, "size_kb": size_kb, "path": path})
    return files


def _play_with_pygame(filepath: str, volume: int):
    """使用 pygame 播放音频（推荐，支持 MP3/WAV/OGG）"""
    global is_playing, current_process
    try:
        import pygame
        pygame.mixer.init()
        pygame.mixer.music.load(filepath)
        pygame.mixer.music.set_volume(volume / 100.0)
        pygame.mixer.music.play()
        while pygame.mixer.music.get_busy() and is_playing:
            time.sleep(0.2)
        pygame.mixer.music.stop()
        pygame.mixer.quit()
    except Exception as e:
        print(f"[pygame] 播放失败: {e}")
        raise


def _play_with_subprocess(filepath: str, volume: int):
    """使用系统命令播放音频（后备方案）"""
    global current_process, is_playing

    # 尝试不同播放器
    players = [
        ["mpg123", "-q", filepath],           # MP3
        ["aplay", "-q", filepath],             # WAV
        ["ffplay", "-nodisp", "-autoexit", "-volume", str(volume), filepath],
        ["paplay", filepath],                  # PulseAudio
    ]
    for cmd in players:
        try:
            current_process = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            current_process.wait()
            return
        except FileNotFoundError:
            continue
    raise RuntimeError("未找到可用音频播放器，请安装 mpg123 或 pygame")


def play_file(filepath: str, volume: int = DEFAULT_VOLUME):
    """播放音频文件（阻塞，应在后台线程调用）"""
    global is_playing
    with play_lock:
        stop_current()
        is_playing = True

    try:
        _play_with_pygame(filepath, volume)
    except Exception:
        try:
            _play_with_subprocess(filepath, volume)
        except Exception as e:
            print(f"[audio] 所有播放方式均失败: {e}")
    finally:
        is_playing = False


def stop_current():
    """停止当前播放"""
    global is_playing, current_process
    is_playing = False
    try:
        import pygame
        pygame.mixer.music.stop()
        pygame.mixer.quit()
    except Exception:
        pass
    if current_process:
        try:
            current_process.terminate()
        except Exception:
            pass
        current_process = None


def set_volume_pygame(vol: int):
    """设置音量"""
    try:
        import pygame
        pygame.mixer.music.set_volume(vol / 100.0)
    except Exception:
        pass


# ========== API ==========

@app.route("/")
def index():
    files = get_audio_files()
    links = "".join(
        f'<li><a href="/play?file={f["name"]}">{f["name"]}</a> ({f["size_kb"]} KB)</li>'
        for f in files
    )
    return f"""<html><body style="font-family:sans-serif;padding:20px">
<h2>车载音频播放服务</h2>
<p>音量: {current_volume} | 状态: {'播放中' if is_playing else '空闲'}</p>
<ol>{links}</ol>
<p><i>将 MP3/WAV/OGG 文件放入 audio_files 目录即可自动识别</i></p>
</body></html>"""


@app.route("/list")
def api_list():
    """列出可用音频文件"""
    return jsonify({
        "files": [{f["name"]: f["size_kb"]} for f in get_audio_files()],
        "count": len(get_audio_files()),
        "playing": is_playing,
    })


@app.route("/play")
def api_play():
    """播放音频文件: /play?file=xxx.mp3"""
    global current_volume
    filename = request.args.get("file", "").strip()
    vol = request.args.get("volume", type=int, default=current_volume)
    current_volume = vol

    if not filename:
        # 没有指定文件，尝试播放第一个
        files = get_audio_files()
        if not files:
            return jsonify({"status": "error", "message": "没有可用的音频文件，请放入 audio_files 目录"}), 404
        filename = files[0]["name"]

    filepath = os.path.join(AUDIO_DIR, filename)
    if not os.path.exists(filepath):
        return jsonify({
            "status": "error",
            "message": f"文件不存在: {filename}",
            "available": [f["name"] for f in get_audio_files()],
        }), 404

    thread = threading.Thread(target=play_file, args=(filepath, vol), daemon=True)
    thread.start()
    time.sleep(0.3)
    return jsonify({"status": "playing" if is_playing else "error", "file": filename, "volume": vol})


@app.route("/stop")
def api_stop():
    """停止播放"""
    stop_current()
    return jsonify({"status": "stopped"})


@app.route("/volume")
def api_volume():
    """设置/获取音量: /volume?level=80"""
    global current_volume
    level = request.args.get("level", type=int)
    if level is not None:
        current_volume = max(0, min(100, level))
        set_volume_pygame(current_volume)
    return jsonify({"volume": current_volume})


@app.route("/status")
def api_status():
    """播放状态"""
    return jsonify({
        "playing": is_playing,
        "volume": current_volume,
        "files": len(get_audio_files()),
    })


if __name__ == "__main__":
    # 安装依赖提示
    try:
        import pygame
        print("pygame 已加载，音频播放就绪")
    except ImportError:
        print("[INFO] pygame 未安装，将使用系统播放器。建议: pip3 install pygame")

    files = get_audio_files()
    print(f"音频目录: {AUDIO_DIR}")
    print(f"已发现 {len(files)} 个音频文件")
    for f in files:
        print(f"  - {f['name']} ({f['size_kb']} KB)")

    print(f"启动音频播放服务，监听 0.0.0.0:5002")
    app.run(host="0.0.0.0", port=5002, debug=False)
