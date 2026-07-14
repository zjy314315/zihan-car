#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
适用于 Ubuntu 智能小车的实时人脸识别服务。

功能：
1. 使用摄像头实时检测人脸
2. 使用 OpenCV DNN + OpenFace 模型提取人脸特征
3. 与已注册的人脸库进行比对，识别身份
4. 通过 HTTP 接口控制识别开关、注册新用户、查询当前结果

运行方式：
    python3 car_face_recognition.py

接口示例：
    开始识别： curl -X POST http://127.0.0.1:5000/start
    停止识别： curl -X POST http://127.0.0.1:5000/stop
    查看状态： curl http://127.0.0.1:5000/status
    注册人脸： curl -X POST http://127.0.0.1:5000/register -H "Content-Type: application/json" -d '{"name":"张三"}'
"""

import json
import os
import threading
import time
from typing import Dict, List

import cv2
import numpy as np
from flask import Flask, jsonify, request, send_from_directory


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
MODEL_DIR = os.path.join(SCRIPT_DIR, "dnn_models")
KNOWN_FACES_FILE = os.path.join(SCRIPT_DIR, "known_faces.json")


class FaceRecognitionService:
    def __init__(self):
        self.face_detector_net = None
        self.face_recognition_net = None
        self.face_detector_prototxt = os.path.join(MODEL_DIR, "opencv_face_detector.pbtxt")
        self.face_detector_weights = os.path.join(MODEL_DIR, "opencv_face_detector_uint8.pb")
        self.face_recognition_model = os.path.join(MODEL_DIR, "nn4.small2.v1.t7")
        self.face_threshold = 0.8
        self.detector_confidence = 0.7
        self.known_faces: List[Dict] = []
        self.running = False
        self.thread = None
        self.capture = None
        self.latest_result = {
            "status": "idle",
            "name": "unknown",
            "distance": None,
            "confidence": None,
            "bbox": None,
            "timestamp": None,
        }
        self.lock = threading.Lock()

        self._load_models()
        self.known_faces = self._load_known_faces()

    def _load_models(self) -> None:
        if not os.path.exists(self.face_detector_prototxt):
            raise FileNotFoundError(f"未找到人脸检测配置文件: {self.face_detector_prototxt}")
        if not os.path.exists(self.face_detector_weights):
            raise FileNotFoundError(f"未找到人脸检测权重文件: {self.face_detector_weights}")
        if not os.path.exists(self.face_recognition_model):
            raise FileNotFoundError(f"未找到人脸识别模型文件: {self.face_recognition_model}")

        self.face_detector_net = cv2.dnn.readNet(self.face_detector_weights, self.face_detector_prototxt)
        self.face_recognition_net = cv2.dnn.readNetFromTorch(self.face_recognition_model)
        print("模型加载完成")

    def _load_known_faces(self) -> List[Dict]:
        if not os.path.exists(KNOWN_FACES_FILE):
            return []
        try:
            with open(KNOWN_FACES_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
            return data
        except Exception as e:
            print(f"读取已知人脸文件失败: {e}")
            return []

    def _save_known_faces(self) -> None:
        with open(KNOWN_FACES_FILE, "w", encoding="utf-8") as f:
            json.dump(self.known_faces, f, ensure_ascii=False, indent=2)

    def detect_faces(self, frame: np.ndarray) -> List[Dict]:
        if self.face_detector_net is None:
            return []

        h, w = frame.shape[:2]
        blob = cv2.dnn.blobFromImage(
            cv2.resize(frame, (300, 300)),
            1.0,
            (300, 300),
            (104.0, 177.0, 123.0),
            swapRB=False,
            crop=False,
        )
        self.face_detector_net.setInput(blob)
        detections = self.face_detector_net.forward()

        results = []
        for i in range(detections.shape[2]):
            confidence = float(detections[0, 0, i, 2])
            if confidence > self.detector_confidence:
                box = detections[0, 0, i, 3:7] * np.array([w, h, w, h])
                x1, y1, x2, y2 = box.astype("int")
                results.append({
                    "box_coords": [int(x1), int(y1), int(x2), int(y2)],
                    "confidence": confidence,
                })
        return results

    def extract_face_features(self, face_image: np.ndarray) -> np.ndarray:
        if self.face_recognition_net is None:
            return np.array([])

        face_blob = cv2.dnn.blobFromImage(
            cv2.resize(face_image, (96, 96)),
            1.0 / 255,
            (96, 96),
            (0, 0, 0),
            swapRB=True,
            crop=False,
        )
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
        faces = self.detect_faces(frame)
        if not faces:
            return {
                "status": "no_face",
                "name": "unknown",
                "distance": None,
                "confidence": None,
                "bbox": None,
            }

        best_face = max(faces, key=lambda item: item["confidence"])
        crop = self._crop_face(frame, best_face["box_coords"])
        if crop.size == 0:
            return {
                "status": "no_face",
                "name": "unknown",
                "distance": None,
                "confidence": None,
                "bbox": best_face["box_coords"],
            }

        feature = self.extract_face_features(crop)
        if feature.size == 0:
            return {
                "status": "feature_error",
                "name": "unknown",
                "distance": None,
                "confidence": best_face["confidence"],
                "bbox": best_face["box_coords"],
            }

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
            best_distance = best_distance if best_distance is not None else None

        return {
            "status": status,
            "name": best_name,
            "distance": best_distance,
            "confidence": best_face["confidence"],
            "bbox": best_face["box_coords"],
        }

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
        self.known_faces.append({
            "name": name.strip(),
            "embedding": embedding.tolist(),
        })
        self._save_known_faces()
        return {"status": "success", "message": f"已注册用户 {name}", "count": len(embeddings)}

    def _run_loop(self) -> None:
        self.capture = cv2.VideoCapture(0)
        if not self.capture.isOpened():
            with self.lock:
                self.latest_result = {
                    "status": "camera_error",
                    "name": "unknown",
                    "distance": None,
                    "confidence": None,
                    "bbox": None,
                }
            self.running = False
            return

        while self.running:
            ret, frame = self.capture.read()
            if not ret:
                break
            result = self.recognize_frame(frame)
            with self.lock:
                self.latest_result = {
                    **result,
                    "timestamp": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime()),
                }
            time.sleep(0.05)

        if self.capture is not None:
            self.capture.release()
            self.capture = None

        with self.lock:
            self.latest_result = {
                **self.latest_result,
                "status": "stopped",
            }

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

    def get_status(self) -> Dict:
        with self.lock:
            return {
                "running": self.running,
                "known_faces": [item.get("name") for item in self.known_faces],
                "latest_result": self.latest_result,
            }


service = FaceRecognitionService()
app = Flask(__name__)


@app.route("/")
def index():
    return send_from_directory(SCRIPT_DIR, "index.html")


@app.route("/start", methods=["POST"])
def api_start():
    return jsonify(service.start())


@app.route("/stop", methods=["POST"])
def api_stop():
    return jsonify(service.stop())


@app.route("/status")
def api_status():
    return jsonify(service.get_status())


@app.route("/register", methods=["POST"])
def api_register():
    payload = request.get_json(silent=True) or {}
    name = payload.get("name", "")
    return jsonify(service.register_face(name))


@app.route("/result")
def api_result():
    return jsonify(service.get_status()["latest_result"])


if __name__ == "__main__":
    print("启动人脸识别服务，监听 0.0.0.0:5000")
    app.run(host="0.0.0.0", port=5000, debug=False)
