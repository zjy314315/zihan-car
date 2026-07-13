#!/usr/bin/env python3
"""
iCar 统一主服务
一键启动：视频推流 + 人脸识别 + YOLO检测 + 摔倒检测 + 音频播放

运行：
    python3 car_main.py

所有功能一个端口 5000：
    /video_feed      - MJPEG 视频流（App WebView 用）
    /index2          - 视频页面
    /start           - 开始人脸识别
    /stop            - 停止
    /register        - 注册人脸
    /status          - 查看状态
    /result          - 查看结果
    /start_fall      - 启用摔倒检测
    /stop_fall       - 停用摔倒检测
    /start_all       - 一键启动全部
    /audio/list      - 音频列表
    /audio/play      - 播放音频
    /audio/stop      - 停止音频
    /audio/volume    - 调节音量
"""

import os
import sys
import json
import glob
import time
import threading
import subprocess
import signal
from typing import Optional, List, Dict

import cv2
import numpy as np
from flask import Flask, request, jsonify, Response, render_template_string

# YOLO
try:
    from ultralytics import YOLO
    YOLO_AVAILABLE = True
except Exception:
    YOLO_AVAILABLE = False

# Audio
try:
    import pygame
    PYGAME_AVAILABLE = True
except Exception:
    PYGAME_AVAILABLE = False

# ========== 配置 ==========
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
MODEL_DIR = os.path.join(SCRIPT_DIR, "dnn_models")
AUDIO_DIR = os.path.join(SCRIPT_DIR, "audio_files")
KNOWN_FACES_FILE = os.path.join(SCRIPT_DIR, "known_faces.json")
YOLO_MODEL = os.path.join(SCRIPT_DIR, "yolov8n.pt")

CAMERA_DEVICE = "/dev/video0"
FRAME_WIDTH = 480
FRAME_HEIGHT = 360
SERVICE_PORT = 5000

os.makedirs(AUDIO_DIR, exist_ok=True)

# ========== AI 服务 ==========
class AIService:
    def __init__(self):
        self.face_net = None
        self.face_recog_net = None
        self.yolo_model = None

        self.face_enabled = False
        self.yolo_enabled = False
        self.fall_enabled = False

        self.known_faces: List[Dict] = []
        self.latest_frame = None
        self.frame_lock = threading.Lock()
        self.result_lock = threading.Lock()

        self.latest_result = {
            "face": {"status": "idle", "name": "unknown"},
            "yolo": {"enabled": False, "people": []},
            "fall": {"enabled": False, "status": "idle", "confidence": 0.0},
            "timestamp": None,
        }

        self.fall_history = 0
        self.prev_aspect = None

        self._load_models()
        self.known_faces = self._load_faces()

    def _load_models(self):
        face_pb = os.path.join(MODEL_DIR, "opencv_face_detector_uint8.pb")
        face_pbtxt = os.path.join(MODEL_DIR, "opencv_face_detector.pbtxt")
        if os.path.exists(face_pb):
            self.face_net = cv2.dnn.readNet(face_pb, face_pbtxt)

        recog_model = os.path.join(MODEL_DIR, "nn4.small2.v1.t7")
        if os.path.exists(recog_model):
            self.face_recog_net = cv2.dnn.readNetFromTorch(recog_model)

        if YOLO_AVAILABLE and os.path.exists(YOLO_MODEL):
            self.yolo_model = YOLO(YOLO_MODEL)
            print("[AI] YOLO 模型加载完成")
        else:
            print("[AI] YOLO 未加载（将使用 SSD 检测）")

        print("[AI] 模型加载完成")

    def _load_faces(self):
        if not os.path.exists(KNOWN_FACES_FILE):
            return []
        try:
            with open(KNOWN_FACES_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return []

    def _save_faces(self):
        with open(KNOWN_FACES_FILE, "w", encoding="utf-8") as f:
            json.dump(self.known_faces, f, ensure_ascii=False, indent=2)

    def set_frame(self, frame):
        with self.frame_lock:
            self.latest_frame = frame.copy()

    def get_frame(self):
        with self.frame_lock:
            return self.latest_frame.copy() if self.latest_frame is not None else None

    def process(self):
        """主处理循环（在独立线程中运行）"""
        while True:
            frame = self.get_frame()
            if frame is None:
                time.sleep(0.05)
                continue

            face_result = {"status": "face_disabled", "name": "unknown"}
            yolo_people: List[Dict] = []
            fall_result = {"enabled": False, "status": "fall_disabled", "confidence": 0.0}

            if self.face_enabled:
                face_result = self._detect_face(frame)

            if self.yolo_enabled:
                yolo_people = self._detect_people(frame)

            if self.fall_enabled:
                fall_result = self._detect_fall(yolo_people)

            with self.result_lock:
                self.latest_result = {
                    "face": face_result,
                    "yolo": {"enabled": self.yolo_enabled, "people": yolo_people},
                    "fall": fall_result,
                    "timestamp": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime()),
                }

            time.sleep(0.05)

    def _detect_face(self, frame):
        if self.face_net is None:
            return {"status": "model_error", "name": "unknown"}
        h, w = frame.shape[:2]
        blob = cv2.dnn.blobFromImage(cv2.resize(frame, (300, 300)), 1.0, (300, 300), (104.0, 177.0, 123.0), swapRB=False)
        self.face_net.setInput(blob)
        dets = self.face_net.forward()
        faces = []
        for i in range(dets.shape[2]):
            conf = float(dets[0, 0, i, 2])
            if conf > 0.7:
                box = dets[0, 0, i, 3:7] * np.array([w, h, w, h])
                x1, y1, x2, y2 = box.astype("int")
                faces.append({"box": [int(x1), int(y1), int(x2), int(y2)], "conf": conf})
        if not faces:
            return {"status": "no_face", "name": "unknown"}

        best = max(faces, key=lambda f: f["conf"])
        x1, y1, x2, y2 = best["box"]
        x1, y1 = max(0, x1), max(0, y1)
        x2, y2 = min(w, x2), min(h, y2)
        crop = frame[y1:y2, x1:x2]
        if crop.size == 0:
            return {"status": "no_face", "name": "unknown"}

        if self.face_recog_net is not None:
            blob2 = cv2.dnn.blobFromImage(cv2.resize(crop, (96, 96)), 1.0/255, (96, 96), (0, 0, 0), swapRB=True)
            self.face_recog_net.setInput(blob2)
            feat = self.face_recog_net.forward().flatten()

            best_name, best_dist = "unknown", None
            for item in self.known_faces:
                emb = np.array(item.get("embedding", []), dtype=np.float32)
                if emb.shape == feat.shape:
                    d = float(np.linalg.norm(feat - emb))
                    if best_dist is None or d < best_dist:
                        best_dist, best_name = d, item.get("name", "unknown")
            if best_dist is not None and best_dist < 0.8:
                return {"status": "recognized", "name": best_name}
        return {"status": "unknown", "name": "unknown"}

    def _detect_people(self, frame):
        if self.yolo_model is not None:
            results = self.yolo_model(frame, stream=False, conf=0.5, verbose=False)
            people = []
            for r in results:
                for box in r.boxes:
                    if int(box.cls[0]) == 0:  # person class
                        x1, y1, x2, y2 = map(int, box.xyxy[0])
                        people.append({"box": [x1, y1, x2, y2], "conf": float(box.conf[0])})
            return people
        return []

    def _detect_fall(self, people):
        if not people:
            self.prev_aspect = None
            return {"enabled": True, "status": "no_person", "confidence": 0.0}

        best = max(people, key=lambda p: p["conf"])
        x1, y1, x2, y2 = best["box"]
        w = max(1, x2 - x1)
        h = max(1, y2 - y1)
        ratio = h / float(w)

        if self.prev_aspect is None:
            self.prev_aspect = ratio
            return {"enabled": True, "status": "monitoring", "confidence": 0.0}

        delta = self.prev_aspect - ratio
        self.prev_aspect = ratio

        if delta > 0.8 and ratio < 1.0:
            self.fall_history += 1
            if self.fall_history >= 3:
                return {"enabled": True, "status": "fall_detected", "confidence": min(1.0, delta)}
        else:
            self.fall_history = 0
        return {"enabled": True, "status": "normal", "confidence": 0.0}

    def register_face(self, name: str):
        if not name or not name.strip():
            return {"status": "error", "message": "姓名不能为空"}
        frame = self.get_frame()
        if frame is None:
            return {"status": "error", "message": "摄像头未就绪，请稍后重试"}

        faces_result = self._detect_face(frame)
        if faces_result["status"] != "recognized" and faces_result["status"] != "unknown":
            return {"status": "error", "message": "未检测到人脸，请正对摄像头"}

        # 从最新帧提取特征
        h, w = frame.shape[:2]
        blob = cv2.dnn.blobFromImage(cv2.resize(frame, (300, 300)), 1.0, (300, 300), (104.0, 177.0, 123.0), swapRB=False)
        self.face_net.setInput(blob)
        dets = self.face_net.forward()
        faces = []
        for i in range(dets.shape[2]):
            if float(dets[0, 0, i, 2]) > 0.7:
                box = dets[0, 0, i, 3:7] * np.array([w, h, w, h])
                faces.append(box.astype("int"))

        if not faces:
            return {"status": "error", "message": "未检测到人脸"}

        x1, y1, x2, y2 = faces[0]
        x1, y1 = max(0, x1), max(0, y1)
        x2, y2 = min(w, x2), min(h, y2)
        crop = frame[y1:y2, x1:x2]

        if self.face_recog_net is not None and crop.size > 0:
            blob2 = cv2.dnn.blobFromImage(cv2.resize(crop, (96, 96)), 1.0/255, (96, 96), (0, 0, 0), swapRB=True)
            self.face_recog_net.setInput(blob2)
            feat = self.face_recog_net.forward().flatten()
            self.known_faces.append({"name": name.strip(), "embedding": feat.tolist()})
            self._save_faces()
            return {"status": "success", "message": f"已注册用户 {name}"}

        return {"status": "error", "message": "特征提取失败"}


# ========== 音频服务 ==========
class AudioService:
    """音频播放（使用 aplay 直接输出到 USB 音箱 card 0）"""
    AUDIO_DEVICE = "plughw:0,0"  # USB Audio Device (C-Media)

    def __init__(self):
        self.playing = False
        self.volume = 70
        self.current_file = ""
        self.process: Optional[subprocess.Popen] = None

    def get_files(self):
        files = []
        for ext in ["*.wav", "*.mp3", "*.ogg", "*.flac", "*.m4a"]:
            for path in sorted(glob.glob(os.path.join(AUDIO_DIR, ext))):
                name = os.path.basename(path)
                files.append({"name": name, "size_kb": round(os.path.getsize(path)/1024, 1)})
        return files

    def play(self, filename: str):
        self.stop()
        filepath = os.path.join(AUDIO_DIR, filename)
        if not os.path.exists(filepath):
            print(f"[Audio] 文件不存在: {filepath}")
            return False

        print(f"[Audio] 播放: {filename} (设备: {self.AUDIO_DEVICE})")
        self.playing = True
        self.current_file = filename

        # 使用 aplay 直接输出到 USB 音箱，音量用 softvol 百分比
        vol_pct = max(0, min(100, self.volume))
        cmd = ["aplay", "-D", self.AUDIO_DEVICE, filepath]
        self.process = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        def _wait():
            if self.process:
                self.process.wait()
            self.playing = False
            print(f"[Audio] 播放完毕: {filename}")

        threading.Thread(target=_wait, daemon=True).start()
        time.sleep(0.3)
        return True

    def stop(self):
        print("[Audio] 停止播放")
        self.playing = False
        if self.process:
            try:
                self.process.terminate()
                time.sleep(0.1)
            except Exception:
                pass
            self.process = None
        # 确保杀掉所有 aplay 进程
        subprocess.run(["pkill", "-f", "aplay"], capture_output=True)
        self.current_file = ""

    def set_vol(self, v: int):
        self.volume = max(0, min(100, v))
        # USB Audio PCM 范围: 0-37
        vol_raw = int(self.volume * 37 / 100)
        subprocess.run(["amixer", "-c", "0", "sset", "PCM", str(vol_raw)],
                       capture_output=True)
        print(f"[Audio] 音量: {self.volume}% (PCM: {vol_raw}/37)")
        try:
            if PYGAME_AVAILABLE:
                pygame.mixer.music.set_volume(self.volume / 100.0)
        except Exception:
            pass


# ========== 视频：直连摄像头 → AI + MJPEG 推流 ==========
CAMERA_DEV = "/dev/video1"
CAMERA_W = 640
CAMERA_H = 480
CAMERA_FPS = 25

# 全局 JPEG 缓存
_latest_jpeg: bytes = b''
_jpeg_lock = threading.Lock()
_jpeg_available = False


def camera_loop(ai_service: AIService):
    """主摄像头循环：捕获帧 → AI处理 + JPEG缓存"""
    global _latest_jpeg, _jpeg_available
    print(f"[Camera] 打开 {CAMERA_DEV}...")

    for dev in [CAMERA_DEV, "/dev/video0", 0, 1]:
        cap = cv2.VideoCapture(dev)
        if cap.isOpened():
            print(f"[Camera] {dev} 已打开")
            break
        cap.release()
    else:
        print("[Camera] FATAL: 无法打开任何摄像头!")
        return

    cap.set(cv2.CAP_PROP_FRAME_WIDTH, CAMERA_W)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, CAMERA_H)
    cap.set(cv2.CAP_PROP_FPS, CAMERA_FPS)

    frame_interval = 1.0 / CAMERA_FPS
    last_time = time.time()

    while True:
        ret, frame = cap.read()
        if not ret:
            print("[Camera] 读取失败，重试...")
            time.sleep(0.5)
            continue

        # 送 AI 处理
        ai_service.set_frame(cv2.resize(frame, (FRAME_WIDTH, FRAME_HEIGHT)))

        # 编码 JPEG 缓存
        now = time.time()
        if now - last_time >= frame_interval:
            _, jpg = cv2.imencode('.jpg', frame, [cv2.IMWRITE_JPEG_QUALITY, 75])
            with _jpeg_lock:
                _latest_jpeg = jpg.tobytes()
                _jpeg_available = True
            last_time = now


def generate_frames():
    """MJPEG 视频流（从缓存读取）"""
    global _latest_jpeg, _jpeg_available
    while True:
        with _jpeg_lock:
            if _jpeg_available and _latest_jpeg:
                jpg = _latest_jpeg
            else:
                jpg = None
        if jpg:
            yield (b'--frame\r\n'
                   b'Content-Type: image/jpeg\r\n\r\n' + jpg + b'\r\n')
            time.sleep(0.04)
        else:
            time.sleep(0.1)


# ========== Flask App ==========
ai_service = AIService()
audio_service = AudioService()
app = Flask(__name__)

INDEX2_HTML = '''<!DOCTYPE html><html><head><meta charset="utf-8"><title>iCar Video</title>
<style>body{margin:0;background:#000}img{width:100%;height:auto;display:block}</style></head>
<body><img src="/video_feed"></body></html>'''


@app.route("/")
def index():
    return render_template_string(INDEX2_HTML)


@app.route("/index2")
def index2():
    return render_template_string(INDEX2_HTML)


@app.route("/video_feed")
def video_feed():
    return Response(generate_frames(),
                    mimetype='multipart/x-mixed-replace; boundary=frame')


# --- AI API ---
@app.route("/status")
def api_status():
    with ai_service.result_lock:
        result = dict(ai_service.latest_result)
    return jsonify({
        "running": True,
        "face_enabled": ai_service.face_enabled,
        "yolo_enabled": ai_service.yolo_enabled,
        "fall_enabled": ai_service.fall_enabled,
        "known_faces": [f.get("name") for f in ai_service.known_faces],
        "latest_result": result,
    })


@app.route("/result")
def api_result():
    with ai_service.result_lock:
        return jsonify(dict(ai_service.latest_result))


@app.route("/register", methods=["POST"])
def api_register():
    payload = request.get_json(silent=True) or {}
    name = payload.get("name", "")
    return jsonify(ai_service.register_face(name))


@app.route("/start", methods=["POST"])
def api_start():
    ai_service.face_enabled = True
    return jsonify({"status": "started"})


@app.route("/stop", methods=["POST"])
def api_stop():
    ai_service.face_enabled = False
    return jsonify({"status": "stopped"})


@app.route("/start_face", methods=["POST"])
def api_start_face():
    ai_service.face_enabled = True
    return jsonify({"status": "face_enabled"})


@app.route("/stop_face", methods=["POST"])
def api_stop_face():
    ai_service.face_enabled = False
    return jsonify({"status": "face_disabled"})


@app.route("/start_yolo", methods=["POST"])
def api_start_yolo():
    ai_service.yolo_enabled = True
    return jsonify({"status": "yolo_enabled"})


@app.route("/stop_yolo", methods=["POST"])
def api_stop_yolo():
    ai_service.yolo_enabled = False
    return jsonify({"status": "yolo_disabled"})


@app.route("/start_fall", methods=["POST"])
def api_start_fall():
    ai_service.fall_enabled = True
    return jsonify({"status": "fall_enabled"})


@app.route("/stop_fall", methods=["POST"])
def api_stop_fall():
    ai_service.fall_enabled = False
    return jsonify({"status": "fall_disabled"})


@app.route("/start_all", methods=["POST"])
def api_start_all():
    ai_service.face_enabled = True
    ai_service.yolo_enabled = True
    ai_service.fall_enabled = True
    return jsonify({"status": "all_started"})


# --- 音频 API ---
@app.route("/audio/list")
def audio_list():
    files = audio_service.get_files()
    # Return both JSON and plain text format
    fmt = request.args.get("fmt", "json")
    if fmt == "text":
        return "\n".join([f["name"] for f in files]), 200, {"Content-Type": "text/plain; charset=utf-8"}
    return jsonify({
        "files": [f["name"] for f in files],
        "count": len(files),
        "playing": audio_service.playing
    })


@app.route("/audio/play")
def audio_play():
    filename = request.args.get("file", "").strip()
    vol = request.args.get("volume", type=int, default=audio_service.volume)
    audio_service.set_vol(vol)
    if not filename:
        files = audio_service.get_files()
        if not files:
            return jsonify({"status": "error", "message": "没有音频文件"}), 404
        filename = files[0]["name"]
    ok = audio_service.play(filename)
    return jsonify({"status": "playing" if ok else "error", "file": filename})


@app.route("/audio/stop")
def audio_stop():
    audio_service.stop()
    return jsonify({"status": "stopped"})


@app.route("/audio/volume")
def audio_volume():
    level = request.args.get("level", type=int)
    if level is not None:
        audio_service.set_vol(level)
    return jsonify({"volume": audio_service.volume})


@app.route("/audio/status")
def audio_status():
    return jsonify({
        "playing": audio_service.playing,
        "volume": audio_service.volume,
        "file": audio_service.current_file,
        "files": len(audio_service.get_files()),
    })


# ========== 启动 ==========

@app.route("/video_page")
def video_page():
    return '''<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<style>body{margin:0;background:#000;display:flex;align-items:center;justify-content:center;height:100vh;overflow:hidden}
img{width:100%;height:auto;display:block}</style></head>
<body><img id="v" src="/snapshot"><script>
setInterval(function(){document.getElementById("v").src="/snapshot?t="+Date.now()},200)
</script></body></html>'''


@app.route("/snapshot")
def snapshot():
    frame = ai_service.get_frame()
    if frame is None:
        return "no frame", 503
    _, jpg = cv2.imencode('.jpg', frame, [cv2.IMWRITE_JPEG_QUALITY, 70])
    return Response(jpg.tobytes(), mimetype='image/jpeg')



if __name__ == "__main__":
    print("=" * 50)
    print("  iCar 统一主服务")
    print(f"  摄像头: {CAMERA_DEV}")
    print(f"  端口: {SERVICE_PORT}")
    print("=" * 50)

    # 启动摄像头线程（直连摄像头，同时给 AI + 视频流）
    cam_thread = threading.Thread(target=camera_loop, args=(ai_service,), daemon=True)
    cam_thread.start()
    print("[OK] 摄像头线程已启动")

    # 启动 AI 处理线程
    ai_thread = threading.Thread(target=ai_service.process, daemon=True)
    ai_thread.start()
    print("[OK] AI 处理线程已启动")

    # 音频文件扫描
    files = audio_service.get_files()
    print(f"[OK] 音频服务就绪 ({len(files)} 个文件)")

    # 启动 Flask
    print(f"[OK] 服务启动: http://0.0.0.0:{SERVICE_PORT}")
    print("  视频: /video_feed /index2")
    print("  AI: /status /result /start /stop /register /start_fall /start_all")
    print("  音频: /audio/list /audio/play /audio/stop /audio/volume")
    print("=" * 50)

    try:
        app.run(host="0.0.0.0", port=SERVICE_PORT, debug=False, threaded=True)
    except KeyboardInterrupt:
        print("\n[EXIT] 服务已停止")
