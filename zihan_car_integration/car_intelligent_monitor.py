#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
统一智能监控服务：
- 人脸识别
- YOLO/SSD 人体检测
- 摔倒判断
- 通过网页控制

运行方式：
    python3 car_intelligent_monitor.py

或：
    bash run_car_ai.sh
"""

import json
import os
import threading
import time
from typing import Dict, List

import cv2
import numpy as np
from flask import Flask, jsonify, request, send_from_directory

try:
    from ultralytics import YOLO
    YOLO_AVAILABLE = True
except Exception:
    YOLO_AVAILABLE = False


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
MODEL_DIR = os.path.join(SCRIPT_DIR, "dnn_models")
KNOWN_FACES_FILE = os.path.join(SCRIPT_DIR, "known_faces.json")
YOLO_MODEL_PATH = os.path.join(SCRIPT_DIR, "yolov8n.pt")
PERSON_PROTO = os.path.join(MODEL_DIR, "MobileNetSSD_deploy.prototxt")
PERSON_MODEL = os.path.join(MODEL_DIR, "MobileNetSSD_deploy.caffemodel")
FACE_PROTO = os.path.join(MODEL_DIR, "opencv_face_detector.pbtxt")
FACE_MODEL = os.path.join(MODEL_DIR, "opencv_face_detector_uint8.pb")
FACE_RECOGNITION_MODEL = os.path.join(MODEL_DIR, "nn4.small2.v1.t7")


class IntelligentMonitorService:
    def __init__(self):
        self.face_detector_net = None
        self.face_recognition_net = None
        self.person_detector_net = None
        self.yolo_model = None

        self.face_enabled = False
        self.yolo_enabled = False
        self.fall_enabled = False
        self.running = False
        self.thread = None
        self.capture = None
        self.lock = threading.Lock()

        self.known_faces: List[Dict] = []
        self.latest_result = {
            "face": {"status": "idle", "name": "unknown"},
            "yolo": {"enabled": False, "people": []},
            "fall": {"enabled": False, "status": "idle", "confidence": 0.0},
            "timestamp": None,
        }

        self.fall_history: List[Dict] = []
        self.fall_counter = 0
        self.previous_person = None

        self.face_threshold = 0.8
        self.detector_confidence = 0.7

        self._load_models()
        self.known_faces = self._load_known_faces()

    def _load_models(self):
        # face models
        if os.path.exists(FACE_PROTO) and os.path.exists(FACE_MODEL):
            self.face_detector_net = cv2.dnn.readNet(FACE_MODEL, FACE_PROTO)
        if os.path.exists(FACE_RECOGNITION_MODEL):
            self.face_recognition_net = cv2.dnn.readNetFromTorch(FACE_RECOGNITION_MODEL)

        # person detector fallback (SSD)
        if os.path.exists(PERSON_PROTO) and os.path.exists(PERSON_MODEL):
            self.person_detector_net = cv2.dnn.readNetFromCaffe(PERSON_PROTO, PERSON_MODEL)

        # YOLO optional
        if YOLO_AVAILABLE and os.path.exists(YOLO_MODEL_PATH):
            self.yolo_model = YOLO(YOLO_MODEL_PATH)
            print("YOLO 模型加载完成")
        else:
            print("YOLO 模型未加载，使用 SSD 人体检测作为后备")

    def _load_known_faces(self) -> List[Dict]:
        if not os.path.exists(KNOWN_FACES_FILE):
            return []
        try:
            with open(KNOWN_FACES_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception as e:
            print(f"读取已知人脸文件失败: {e}")
            return []

    def _save_known_faces(self):
        with open(KNOWN_FACES_FILE, "w", encoding="utf-8") as f:
            json.dump(self.known_faces, f, ensure_ascii=False, indent=2)

    def detect_faces(self, frame: np.ndarray) -> List[Dict]:
        if self.face_detector_net is None:
            return []
        h, w = frame.shape[:2]
        blob = cv2.dnn.blobFromImage(cv2.resize(frame, (300, 300)), 1.0, (300, 300), (104.0, 177.0, 123.0), swapRB=False, crop=False)
        self.face_detector_net.setInput(blob)
        detections = self.face_detector_net.forward()
        results = []
        for i in range(detections.shape[2]):
            confidence = float(detections[0, 0, i, 2])
            if confidence > self.detector_confidence:
                box = detections[0, 0, i, 3:7] * np.array([w, h, w, h])
                x1, y1, x2, y2 = box.astype("int")
                results.append({"box_coords": [int(x1), int(y1), int(x2), int(y2)], "confidence": confidence})
        return results

    def extract_face_features(self, face_image: np.ndarray) -> np.ndarray:
        if self.face_recognition_net is None:
            return np.array([])
        face_blob = cv2.dnn.blobFromImage(cv2.resize(face_image, (96, 96)), 1.0 / 255, (96, 96), (0, 0, 0), swapRB=True, crop=False)
        self.face_recognition_net.setInput(face_blob)
        features = self.face_recognition_net.forward()
        return features.flatten()

    def _crop_face(self, frame: np.ndarray, box_coords: List[int]) -> np.ndarray:
        h, w = frame.shape[:2]
        x1, y1, x2, y2 = box_coords
        x1 = max(0, x1)
        y1 = max(0, y1)
        x2 = min(w, x2)
        y2 = min(h, y2)
        return frame[y1:y2, x1:x2]

    def recognize_frame(self, frame: np.ndarray) -> Dict:
        if not self.face_enabled:
            return {"status": "face_disabled", "name": "unknown", "distance": None, "confidence": None, "bbox": None}
        faces = self.detect_faces(frame)
        if not faces:
            return {"status": "no_face", "name": "unknown", "distance": None, "confidence": None, "bbox": None}

        best_face = max(faces, key=lambda item: item["confidence"])
        crop = self._crop_face(frame, best_face["box_coords"])
        if crop.size == 0:
            return {"status": "no_face", "name": "unknown", "distance": None, "confidence": None, "bbox": best_face["box_coords"]}

        feature = self.extract_face_features(crop)
        if feature.size == 0:
            return {"status": "feature_error", "name": "unknown", "distance": None, "confidence": best_face["confidence"], "bbox": best_face["box_coords"]}

        best_name = "unknown"
        best_distance = None
        for item in self.known_faces:
            emb = np.array(item.get("embedding", []), dtype=np.float32)
            if emb.size == 0 or emb.shape != feature.shape:
                continue
            distance = float(np.linalg.norm(feature - emb))
            if best_distance is None or distance < best_distance:
                best_distance = distance
                best_name = item.get("name", "unknown")

        if best_distance is not None and best_distance < self.face_threshold:
            status = "recognized"
        else:
            status = "unknown"
            best_name = "unknown"

        return {"status": status, "name": best_name, "distance": best_distance, "confidence": best_face["confidence"], "bbox": best_face["box_coords"]}

    def register_face(self, name: str, sample_count: int = 5) -> Dict:
        if not name or not name.strip():
            return {"status": "error", "message": "姓名不能为空"}
        cap = cv2.VideoCapture(0)
        if not cap.isOpened():
            return {"status": "error", "message": "无法打开摄像头"}

        embeddings = []
        for _ in range(sample_count):
            ret, frame = cap.read()
            if not ret:
                break
            faces = self.detect_faces(frame)
            if not faces:
                time.sleep(0.2)
                continue
            best_face = max(faces, key=lambda item: item["confidence"])
            crop = self._crop_face(frame, best_face["box_coords"])
            if crop.size == 0:
                continue
            feature = self.extract_face_features(crop)
            if feature.size != 0:
                embeddings.append(feature)
            time.sleep(0.2)

        cap.release()
        if not embeddings:
            return {"status": "error", "message": "没有成功采集到人脸特征"}

        embedding = np.mean(np.stack(embeddings), axis=0)
        self.known_faces.append({"name": name.strip(), "embedding": embedding.tolist()})
        self._save_known_faces()
        return {"status": "success", "message": f"已注册用户 {name}", "count": len(embeddings)}

    def detect_people(self, frame: np.ndarray) -> List[Dict]:
        if self.yolo_model is not None:
            results = self.yolo_model(frame, stream=False, conf=0.5)
            people = []
            for r in results:
                for box in r.boxes:
                    cls_id = int(box.cls[0])
                    label = self.yolo_model.names[cls_id]
                    if label == "person":
                        x1, y1, x2, y2 = map(int, box.xyxy[0])
                        conf = float(box.conf[0])
                        people.append({"box_coords": [x1, y1, x2, y2], "confidence": conf, "label": label})
            return people

        if self.person_detector_net is None:
            return []

        h, w = frame.shape[:2]
        blob = cv2.dnn.blobFromImage(cv2.resize(frame, (300, 300)), 0.007843, (300, 300), 127.5, swapRB=False, crop=False)
        self.person_detector_net.setInput(blob)
        detections = self.person_detector_net.forward()
        people = []
        for i in range(detections.shape[2]):
            confidence = float(detections[0, 0, i, 2])
            if confidence > 0.6:
                idx = int(detections[0, 0, i, 1])
                if idx == 15:
                    box = detections[0, 0, i, 3:7] * np.array([w, h, w, h])
                    x1, y1, x2, y2 = box.astype("int")
                    people.append({"box_coords": [int(x1), int(y1), int(x2), int(y2)], "confidence": confidence, "label": "person"})
        return people

    def detect_fall(self, frame: np.ndarray, people: List[Dict]) -> Dict:
        if not self.fall_enabled:
            return {"status": "fall_disabled", "confidence": 0.0, "detail": "fall_disabled"}
        if not people:
            self.previous_person = None
            return {"status": "no_person", "confidence": 0.0, "detail": "no_person"}

        person = max(people, key=lambda item: item["confidence"])
        x1, y1, x2, y2 = person["box_coords"]
        width = max(1, x2 - x1)
        height = max(1, y2 - y1)
        aspect_ratio = height / float(width)

        if self.previous_person is None:
            self.previous_person = {"aspect_ratio": aspect_ratio, "box": person["box_coords"]}
            return {"status": "monitoring", "confidence": 0.0, "detail": "init"}

        prev_ratio = self.previous_person["aspect_ratio"]
        delta = prev_ratio - aspect_ratio
        self.previous_person = {"aspect_ratio": aspect_ratio, "box": person["box_coords"]}

        if delta > 0.8 and aspect_ratio < 1.0:
            self.fall_counter += 1
            if self.fall_counter >= 2:
                return {"status": "fall_detected", "confidence": min(1.0, delta / 2.0), "detail": "person_fallen"}
        else:
            self.fall_counter = 0
        return {"status": "normal", "confidence": max(0.0, min(1.0, delta / 2.0)), "detail": "monitoring"}

    def _run_loop(self):
        self.capture = cv2.VideoCapture(0)
        if not self.capture.isOpened():
            with self.lock:
                self.latest_result = {
                    "face": {"status": "camera_error", "name": "unknown"},
                    "yolo": {"enabled": self.yolo_enabled, "people": []},
                    "fall": {"enabled": self.fall_enabled, "status": "camera_error", "confidence": 0.0},
                    "timestamp": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime()),
                }
            self.running = False
            return

        while self.running:
            ret, frame = self.capture.read()
            if not ret:
                break
            face_result = self.recognize_frame(frame) if self.face_enabled else {"status": "face_disabled", "name": "unknown", "distance": None, "confidence": None, "bbox": None}
            yolo_result = {"enabled": self.yolo_enabled, "people": []}
            if self.yolo_enabled:
                yolo_result["people"] = self.detect_people(frame)

            fall_result = self.detect_fall(frame, yolo_result["people"]) if self.fall_enabled else {"enabled": False, "status": "fall_disabled", "confidence": 0.0, "detail": "fall_disabled"}

            with self.lock:
                self.latest_result = {
                    "face": face_result,
                    "yolo": yolo_result,
                    "fall": fall_result,
                    "timestamp": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime()),
                }
            time.sleep(0.05)

        if self.capture is not None:
            self.capture.release()
            self.capture = None

        with self.lock:
            self.latest_result["face"] = {"status": "stopped", "name": "unknown"}

    def start(self) -> Dict:
        if self.running:
            return {"status": "already_running"}
        self.running = True
        self.thread = threading.Thread(target=self._run_loop, daemon=True)
        self.thread.start()
        return {"status": "started"}

    def stop(self) -> Dict:
        self.running = False
        if self.thread is not None:
            self.thread.join(timeout=2)
            self.thread = None
        if self.capture is not None:
            self.capture.release()
            self.capture = None
        return {"status": "stopped"}

    def enable_face(self) -> Dict:
        self.face_enabled = True
        return {"status": "face_enabled"}

    def disable_face(self) -> Dict:
        self.face_enabled = False
        return {"status": "face_disabled"}

    def enable_yolo(self) -> Dict:
        self.yolo_enabled = True
        return {"status": "yolo_enabled"}

    def disable_yolo(self) -> Dict:
        self.yolo_enabled = False
        return {"status": "yolo_disabled"}

    def enable_fall(self) -> Dict:
        self.fall_enabled = True
        return {"status": "fall_enabled"}

    def disable_fall(self) -> Dict:
        self.fall_enabled = False
        return {"status": "fall_disabled"}

    def get_status(self) -> Dict:
        with self.lock:
            return {
                "running": self.running,
                "face_enabled": self.face_enabled,
                "yolo_enabled": self.yolo_enabled,
                "fall_enabled": self.fall_enabled,
                "known_faces": [item.get("name") for item in self.known_faces],
                "latest_result": self.latest_result,
            }


service = IntelligentMonitorService()
app = Flask(__name__)


@app.route("/")
def index():
    return send_from_directory(SCRIPT_DIR, "index.html")


@app.route("/status")
def api_status():
    return jsonify(service.get_status())


@app.route("/result")
def api_result():
    return jsonify(service.get_status()["latest_result"])


@app.route("/register", methods=["POST"])
def api_register():
    payload = request.get_json(silent=True) or {}
    name = payload.get("name", "")
    return jsonify(service.register_face(name))


@app.route("/start", methods=["POST"])
def api_start():
    service.enable_face()
    return jsonify(service.start())


@app.route("/stop", methods=["POST"])
def api_stop():
    service.disable_face()
    return jsonify(service.stop())


@app.route("/start_face", methods=["POST"])
def api_start_face():
    service.enable_face()
    return jsonify(service.get_status())


@app.route("/stop_face", methods=["POST"])
def api_stop_face():
    service.disable_face()
    return jsonify(service.get_status())


@app.route("/start_yolo", methods=["POST"])
def api_start_yolo():
    service.enable_yolo()
    return jsonify(service.get_status())


@app.route("/stop_yolo", methods=["POST"])
def api_stop_yolo():
    service.disable_yolo()
    return jsonify(service.get_status())


@app.route("/start_fall", methods=["POST"])
def api_start_fall():
    service.enable_fall()
    return jsonify(service.get_status())


@app.route("/stop_fall", methods=["POST"])
def api_stop_fall():
    service.disable_fall()
    return jsonify(service.get_status())


@app.route("/start_all", methods=["POST"])
def api_start_all():
    service.enable_face()
    service.enable_yolo()
    service.enable_fall()
    return jsonify(service.start())


if __name__ == "__main__":
    print("启动统一智能监控服务，监听 0.0.0.0:5001")
    app.run(host="0.0.0.0", port=5001, debug=False)
