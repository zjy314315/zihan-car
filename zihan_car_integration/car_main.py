#!/usr/bin/env python3
"""
iCar 统一主服务
一键启动：视频推流 + 人脸识别 + YOLO检测 + 摔倒检测(关键点) + 音频播放

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
    /start_fall      - 启用摔倒检测（YOLOv8-pose关键点）
    /stop_fall       - 停用摔倒检测
    /start_all       - 一键启动全部
    /fall/events     - 摔倒事件历史记录
    /audio/list      - 音频列表
    /audio/play      - 播放音频
    /audio/stop      - 停止音频
    /audio/volume    - 调节音量

摔倒检测说明：
    - 优先使用 yolov8n-pose.pt 关键点模型（躯干角度+高宽比+垂直速度）
    - 无姿态模型时自动降级为增强启发式算法（宽高比+位置+宽度）
    - 连续5帧确认 + 30帧冷却，避免重复报警
"""

import os
import sys
import json
import glob
import time
import math
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

# YOLO Pose (for fall detection)
YOLO_POSE_MODEL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "yolov8n-pose.pt")

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
        self.yolo_pose_model = None  # keypoint model for fall detection

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
            "fall": {"enabled": False, "status": "idle", "confidence": 0.0, "detail": ""},
            "timestamp": None,
        }

        # Fall detection state (improved)
        self.fall_history = 0
        self.fall_history_max = 0
        self.fall_events: List[Dict] = []  # timestamped fall event log
        self.prev_shoulder_y = None        # keypoint-based tracking
        self.prev_hip_y = None
        self.person_lost_frames = 0        # track how long person has been missing
        self.last_known_standing = False
        self.fall_cooldown = 0             # cooldown frames after a fall event

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
            print("[AI] YOLO 检测模型加载完成")
        else:
            print("[AI] YOLO 检测模型未加载")

        # Load pose model for fall detection (yolov8n-pose.pt)
        if YOLO_AVAILABLE and os.path.exists(YOLO_POSE_MODEL):
            try:
                self.yolo_pose_model = YOLO(YOLO_POSE_MODEL)
                # Warmup: run a dummy inference to trigger GPU compilation (Jetson: 10-30s)
                print("[AI] YOLO Pose 模型加载完成，预热中...")
                import numpy as np
                dummy = np.zeros((480, 640, 3), dtype=np.uint8)
                self.yolo_pose_model(dummy, stream=False, conf=0.5, verbose=False)
                print("[AI] YOLO Pose 预热完成（摔倒检测增强）")
            except Exception as e:
                print(f"[AI] YOLO Pose 加载失败: {e}，摔倒检测使用增强启发式算法")
        else:
            print("[AI] YOLO Pose 模型未找到，摔倒检测使用增强启发式算法")

        # Also warm up detection model
        if self.yolo_model is not None:
            try:
                import numpy as np
                dummy = np.zeros((480, 640, 3), dtype=np.uint8)
                self.yolo_model(dummy, stream=False, conf=0.5, verbose=False)
                print("[AI] YOLO 检测模型预热完成")
            except Exception:
                pass

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
        frame_counter = 0
        while True:
            frame = self.get_frame()
            if frame is None:
                time.sleep(0.05)
                continue

            frame_counter += 1
            face_result = {"status": "face_disabled", "name": "unknown"}
            yolo_people: List[Dict] = []
            fall_result = {"enabled": False, "status": "fall_disabled", "confidence": 0.0, "detail": ""}

            if self.face_enabled:
                face_result = self._detect_face(frame)

            # Fall detection: use pose model every frame when enabled, or detection model fallback
            if self.fall_enabled and self.yolo_pose_model is not None:
                # Use keypoint-based fall detection (pose model)
                pose_result = self._detect_pose(frame)
                yolo_people = pose_result["people"]
                fall_result = self._detect_fall_from_pose(pose_result["keypoints_list"])
            elif self.yolo_enabled or self.fall_enabled:
                # Use detection model for people, heuristic for fall
                if self.yolo_model is not None:
                    yolo_people = self._detect_people(frame)
                if self.fall_enabled:
                    fall_result = self._detect_fall_improved(yolo_people, frame)

            # Update fall cooldown
            if self.fall_cooldown > 0:
                self.fall_cooldown -= 1

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
        """使用 YOLO 检测模型检测行人"""
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

    # ---- Pose-based detection ----
    def _detect_pose(self, frame):
        """使用 YOLOv8-pose 检测行人和关键点

        通过 .data.cpu().numpy() 转换为 numpy 数组 [N, 17, 3]，
        兼容不同版本的 ultralytics。

        Returns:
            {"people": [...], "keypoints_list": [[{x,y,conf} x 17], ...]}
        """
        people = []
        keypoints_list = []
        if self.yolo_pose_model is None:
            return {"people": people, "keypoints_list": keypoints_list}

        try:
            results = self.yolo_pose_model(frame, stream=False, conf=0.4, verbose=False)
        except Exception as e:
            print(f"[Pose] 模型推理失败: {e}")
            return {"people": people, "keypoints_list": keypoints_list}

        for r in results:
            # Extract person bounding boxes
            if r.boxes is not None:
                for box in r.boxes:
                    if int(box.cls[0]) == 0:  # person
                        x1, y1, x2, y2 = map(int, box.xyxy[0])
                        people.append({"box": [x1, y1, x2, y2], "conf": float(box.conf[0])})

            # Extract keypoints — convert to numpy for reliable cross-version access
            if r.keypoints is not None:
                try:
                    # .data returns tensor [N, 17, 3]; convert to numpy
                    kpts_np = r.keypoints.data
                    if kpts_np is None:
                        continue
                    kpts_np = kpts_np.cpu().numpy()  # shape: [N, 17, 3]
                except Exception as e:
                    print(f"[Pose] 关键点提取失败: {e}")
                    continue

                if kpts_np.ndim != 3:
                    continue

                num_people = kpts_np.shape[0]
                num_kpts = kpts_np.shape[1]  # should be 17 for COCO-pose
                for i in range(num_people):
                    pts = []
                    for j in range(num_kpts):
                        pts.append({
                            "x": float(kpts_np[i, j, 0]),
                            "y": float(kpts_np[i, j, 1]),
                            "conf": float(kpts_np[i, j, 2]),
                        })
                    keypoints_list.append(pts)

        return {"people": people, "keypoints_list": keypoints_list}

    def _detect_fall_from_pose(self, keypoints_list):
        """基于关键点的摔倒检测（简化版）

        关键点索引 (COCO 17点):
          5=左肩, 6=右肩, 11=左髋, 12=右髋, 15=左踝, 16=右踝

        宽松判定 — 满足任一条件即视为疑似摔倒：
          1. 躯干角 > 40°
          2. 高宽比 < 1.3
          3. 肩部下降速度 > 2 px/帧
          4. 髋部低于肩部
          连续 2 帧确认即可报警
        """
        def _safe_kp(kpts, idx, default_conf=-1.0):
            if kpts is None or idx < 0 or idx >= len(kpts):
                return {"x": 0.0, "y": 0.0, "conf": default_conf}
            return kpts[idx]

        if not keypoints_list:
            self.person_lost_frames += 1
            if self.fall_history > 0 and self.person_lost_frames < 10:
                if self.fall_history >= 2:
                    return {"enabled": True, "status": "fall_detected",
                            "confidence": 0.8, "detail": "person_lost_after_fall"}
                return {"enabled": True, "status": "monitoring",
                        "confidence": 0.5, "detail": "tracking_lost"}
            self.fall_history = max(0, self.fall_history - 1)
            return {"enabled": True, "status": "no_person", "confidence": 0.0, "detail": ""}

        self.person_lost_frames = 0

        valid_kpts = [k for k in keypoints_list if len(k) >= 7]

        best_kpts = None
        best_conf_sum = -1
        for kpts in valid_kpts:
            conf_sum = sum(kp["conf"] for kp in kpts)
            if conf_sum > best_conf_sum:
                best_conf_sum = conf_sum
                best_kpts = kpts

        if best_kpts is None:
            return {"enabled": True, "status": "no_person", "confidence": 0.0, "detail": ""}

        kp = best_kpts

        shoulder_l = _safe_kp(kp, 5)
        shoulder_r = _safe_kp(kp, 6)
        hip_l = _safe_kp(kp, 11)
        hip_r = _safe_kp(kp, 12)

        # At least minimal visibility
        shoulder_vis = (shoulder_l["conf"] > 0.3) or (shoulder_r["conf"] > 0.3)
        hip_vis = (hip_l["conf"] > 0.3) or (hip_r["conf"] > 0.3)

        if not shoulder_vis or not hip_vis:
            return {"enabled": True, "status": "monitoring", "confidence": 0.0,
                    "detail": "keypoints_occluded"}

        def mid(pt_a, pt_b):
            return {"x": (pt_a["x"] + pt_b["x"]) / 2.0,
                    "y": (pt_a["y"] + pt_b["y"]) / 2.0}

        shoulder_mid = mid(shoulder_l, shoulder_r)
        hip_mid = mid(hip_l, hip_r)

        # ---- Feature 1: Torso angle ----
        dx = shoulder_mid["x"] - hip_mid["x"]
        dy = shoulder_mid["y"] - hip_mid["y"]
        torso_angle_deg = math.degrees(math.atan2(abs(dx), abs(dy)))

        # ---- Feature 2: Height/width ratio (approximate) ----
        shoulder_width = max(abs(shoulder_r["x"] - shoulder_l["x"]), 1)
        body_height = abs(hip_mid["y"] - shoulder_mid["y"])
        if body_height < 1:
            body_height = 1
        height_width_ratio = body_height / shoulder_width

        # ---- Feature 3: Vertical velocity ----
        shoulder_vel = 0.0
        if self.prev_shoulder_y is not None:
            shoulder_vel = shoulder_mid["y"] - self.prev_shoulder_y  # + = moving down
        self.prev_shoulder_y = shoulder_mid["y"]

        # ---- Feature 4: Hip below shoulder (lying flat) ----
        hip_below_shoulder = hip_mid["y"] > shoulder_mid["y"]

        # ===== SIMPLIFIED: any ONE condition = potential fall =====
        is_standing = torso_angle_deg < 25 and height_width_ratio > 1.5 and not hip_below_shoulder

        trigger_count = 0
        triggers = []

        if torso_angle_deg > 40:
            trigger_count += 1
            triggers.append(f"angle={torso_angle_deg:.0f}°")

        if height_width_ratio < 1.3:
            trigger_count += 1
            triggers.append(f"hw={height_width_ratio:.2f}")

        if shoulder_vel > 2.0:
            trigger_count += 1
            triggers.append(f"vel={shoulder_vel:.1f}")

        if hip_below_shoulder:
            trigger_count += 1
            triggers.append("hip_low")

        is_possible_fall = trigger_count >= 1
        confidence = min(1.0, 0.4 + trigger_count * 0.2)

        # ---- State machine ----
        if is_possible_fall:
            self.fall_history = min(10, self.fall_history + 1)
        elif is_standing:
            self.fall_history = max(0, self.fall_history - 2)
        else:
            self.fall_history = max(0, self.fall_history - 1)

        self.fall_history_max = max(self.fall_history_max, self.fall_history)
        detail = "; ".join(triggers) if triggers else f"angle={torso_angle_deg:.0f}°"

        # Confirm fall: only 2 frames needed, cooldown 15 frames
        if self.fall_history >= 2 and self.fall_cooldown <= 0:
            self.fall_cooldown = 15
            event = {
                "time": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime()),
                "confidence": round(confidence, 3),
                "torso_angle": round(torso_angle_deg, 1),
                "height_width_ratio": round(height_width_ratio, 2),
                "shoulder_vel": round(shoulder_vel, 2),
                "triggers": triggers,
            }
            self.fall_events.append(event)
            if len(self.fall_events) > 50:
                self.fall_events = self.fall_events[-50:]
            # Activate buzzer alarm
            self._trigger_buzzer()
            return {"enabled": True, "status": "fall_detected",
                    "confidence": confidence, "detail": detail}

        if self.fall_history > 0:
            return {"enabled": True, "status": "monitoring",
                    "confidence": confidence, "detail": detail}

        if is_standing:
            return {"enabled": True, "status": "normal", "confidence": 0.0, "detail": detail}
        return {"enabled": True, "status": "monitoring", "confidence": 0.0, "detail": detail}

    def _trigger_buzzer(self):
        """摔倒时触发蜂鸣器报警 3 秒（通过 TCP 发送到 app.py:6000）"""
        try:
            import socket as sock
            s = sock.socket(sock.AF_INET, sock.SOCK_STREAM)
            s.settimeout(1)
            s.connect(("127.0.0.1", 6000))
            # Buzzer ON command: 01=vehicle, 13=buzzer, 04=size, 01=on
            s.send(bytes.fromhex("01130401"))
            s.close()
            print("[Fall] 蜂鸣器 ON")
            # Schedule OFF after 3 seconds
            def _buzzer_off():
                time.sleep(3)
                try:
                    s2 = sock.socket(sock.AF_INET, sock.SOCK_STREAM)
                    s2.settimeout(1)
                    s2.connect(("127.0.0.1", 6000))
                    s2.send(bytes.fromhex("01130400"))  # 00 = off
                    s2.close()
                    print("[Fall] 蜂鸣器 OFF")
                except Exception as e:
                    print(f"[Fall] 蜂鸣器关闭失败: {e}")
            threading.Thread(target=_buzzer_off, daemon=True).start()
        except Exception as e:
            print(f"[Fall] 蜂鸣器触发失败: {e}")

    def _detect_fall_improved(self, people, frame):
        """增强启发式摔倒检测（无姿态模型时，简化阈值）

        任一条件满足即触发：
          宽高比<0.9 / 框在下方>55% / 框宽>画面30%
          连续2帧确认 + 蜂鸣器报警
        """
        h_img, w_img = frame.shape[:2]

        if not people:
            self.person_lost_frames += 1
            if self.fall_history > 0 and self.person_lost_frames < 10:
                if self.fall_history >= 2:
                    return {"enabled": True, "status": "fall_detected",
                            "confidence": 0.7, "detail": "person_lost_after_drop"}
                return {"enabled": True, "status": "monitoring",
                        "confidence": 0.4, "detail": "tracking_lost"}
            self.fall_history = max(0, self.fall_history - 1)
            return {"enabled": True, "status": "no_person", "confidence": 0.0, "detail": ""}

        self.person_lost_frames = 0

        best_score = 0.0
        best_detail = ""

        for person in people:
            x1, y1, x2, y2 = person["box"]
            w = max(1, x2 - x1)
            h = max(1, y2 - y1)
            box_area = w * h

            if box_area < w_img * h_img * 0.003:
                continue

            ratio = h / float(w)
            center_y = (y1 + y2) / 2.0
            rel_y = center_y / h_img
            rel_w = w / w_img

            score = 0.0
            triggers = []

            if ratio < 0.9:
                score += 0.4
                triggers.append(f"ratio={ratio:.2f}")
            if rel_y > 0.55:
                score += 0.2
                triggers.append(f"y={rel_y:.2f}")
            if rel_w > 0.3:
                score += 0.2
                triggers.append(f"w={rel_w:.2f}")

            if score > best_score:
                best_score = score
                best_detail = "; ".join(triggers) if triggers else ""

        # Simplified state machine
        if best_score > 0.25:
            self.fall_history = min(10, self.fall_history + 1)
        elif best_score > 0.1:
            pass  # hold
        else:
            self.fall_history = max(0, self.fall_history - 1)

        self.fall_history_max = max(self.fall_history_max, self.fall_history)

        if self.fall_history >= 2 and self.fall_cooldown <= 0:
            self.fall_cooldown = 15
            conf = min(1.0, best_score + 0.3)
            event = {
                "time": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime()),
                "confidence": round(conf, 3),
                "source": "bbox_heuristic",
            }
            self.fall_events.append(event)
            if len(self.fall_events) > 50:
                self.fall_events = self.fall_events[-50:]
            self._trigger_buzzer()
            return {"enabled": True, "status": "fall_detected",
                    "confidence": conf, "detail": best_detail}

        if self.fall_history > 0:
            return {"enabled": True, "status": "monitoring",
                    "confidence": best_score, "detail": best_detail}

        if best_score < 0.1:
            return {"enabled": True, "status": "normal", "confidence": 0.0, "detail": best_detail}
        return {"enabled": True, "status": "monitoring",
                "confidence": best_score, "detail": best_detail}
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
    """主摄像头循环：捕获帧 → AI处理 + JPEG缓存
    Jetson 上使用 V4L2 设备索引（/dev/video0 = idx 0, /dev/video1 = idx 1）。
    当 /dev/video0 被 app.py 占用时，自动回退到 idx 1。
    """
    global _latest_jpeg, _jpeg_available
    cap = None

    # 优先尝试设备索引（比路径更可靠），先试 idx 1（/dev/video1），再试 idx 0
    for idx in [1, 0]:
        cap = cv2.VideoCapture(idx)
        if cap.isOpened():
            print(f"[Camera] idx={idx} 已打开")
            cap.set(cv2.CAP_PROP_FRAME_WIDTH, CAMERA_W)
            cap.set(cv2.CAP_PROP_FRAME_HEIGHT, CAMERA_H)
            cap.set(cv2.CAP_PROP_FPS, CAMERA_FPS)
            break
        cap.release()
        cap = None

    # 回退：尝试设备路径
    if cap is None:
        for dev in [CAMERA_DEV, "/dev/video0"]:
            cap = cv2.VideoCapture(dev)
            if cap.isOpened():
                print(f"[Camera] {dev} 已打开")
                cap.set(cv2.CAP_PROP_FRAME_WIDTH, CAMERA_W)
                cap.set(cv2.CAP_PROP_FRAME_HEIGHT, CAMERA_H)
                cap.set(cv2.CAP_PROP_FPS, CAMERA_FPS)
                break
            cap.release()
            cap = None

    if cap is None or not cap.isOpened():
        print("[Camera] FATAL: 无法打开任何摄像头!")
        return

    actual_w = cap.get(cv2.CAP_PROP_FRAME_WIDTH)
    actual_h = cap.get(cv2.CAP_PROP_FRAME_HEIGHT)
    print(f"[Camera] 分辨率: {actual_w}x{actual_h}")

    frame_interval = 1.0 / CAMERA_FPS
    last_time = time.time()
    error_count = 0

    while True:
        ret, frame = cap.read()
        if not ret:
            error_count += 1
            if error_count >= 30:
                print("[Camera] 连续读取失败过多，尝试重新打开...")
                cap.release()
                time.sleep(1)
                cap = cv2.VideoCapture(1)
                if not cap.isOpened():
                    cap = cv2.VideoCapture(0)
                error_count = 0
            time.sleep(0.3)
            continue

        error_count = 0

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


@app.route("/fall/events")
def api_fall_events():
    """获取摔倒事件历史记录"""
    limit = request.args.get("limit", 20, type=int)
    events = ai_service.fall_events[-limit:] if ai_service.fall_events else []
    return jsonify({
        "count": len(ai_service.fall_events),
        "events": events,
        "fall_enabled": ai_service.fall_enabled,
        "current_status": ai_service.latest_result.get("fall", {}).get("status", "unknown"),
    })


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
    print("  摔倒: /fall/events (事件历史)")
    print("  音频: /audio/list /audio/play /audio/stop /audio/volume")
    print("=" * 50)

    try:
        app.run(host="0.0.0.0", port=SERVICE_PORT, debug=False, threaded=True)
    except KeyboardInterrupt:
        print("\n[EXIT] 服务已停止")
