#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
统一智能监控服务：
- 人脸识别
- YOLO/SSD 人体检测
- 摔倒判断
- 编队控制（领航-跟随模式）
- 通过网页控制

运行方式：
    python3 car_intelligent_monitor.py

或：
    bash run_car_ai.sh
"""

import json
import os
import socket
import threading
import time
from typing import Dict, List, Optional

import cv2
import numpy as np
from flask import Flask, jsonify, request, send_from_directory

try:
    from ultralytics import YOLO
    YOLO_AVAILABLE = True
except Exception:
    YOLO_AVAILABLE = False

# ONNX runtime for formation control model
try:
    import onnxruntime as ort
    ORT_AVAILABLE = True
except ImportError:
    ORT_AVAILABLE = False

# ROS for direct cmd_vel publishing (formation control)
try:
    import rospy
    from geometry_msgs.msg import Twist
    ROS_AVAILABLE = True
except ImportError:
    ROS_AVAILABLE = False


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
MODEL_DIR = os.path.join(SCRIPT_DIR, "dnn_models")
KNOWN_FACES_FILE = os.path.join(SCRIPT_DIR, "known_faces.json")
YOLO_MODEL_PATH = os.path.join(SCRIPT_DIR, "yolov8n.pt")
PERSON_PROTO = os.path.join(MODEL_DIR, "MobileNetSSD_deploy.prototxt")
PERSON_MODEL = os.path.join(MODEL_DIR, "MobileNetSSD_deploy.caffemodel")
FACE_PROTO = os.path.join(MODEL_DIR, "opencv_face_detector.pbtxt")
FACE_MODEL = os.path.join(MODEL_DIR, "opencv_face_detector_uint8.pb")
FACE_RECOGNITION_MODEL = os.path.join(MODEL_DIR, "nn4.small2.v1.t7")
CAR_MODEL_PATH = "/home/jetson/best.onnx"


# ============================================================
# PID 控制器 (用于编队控制)
# ============================================================
class VelocityPID:
    """Simple PID controller with anti-windup and output clamping."""

    def __init__(self, kp: float, ki: float, kd: float,
                 output_min: float = -1.0, output_max: float = 1.0):
        self.kp = kp
        self.ki = ki
        self.kd = kd
        self.output_min = output_min
        self.output_max = output_max
        self.reset()

    def reset(self):
        self.integral = 0.0
        self.prev_error = 0.0

    def update(self, error: float, dt: float) -> float:
        if dt <= 0:
            dt = 0.05
        self.integral += error * dt
        # anti-windup
        self.integral = max(-1.0, min(1.0, self.integral))
        derivative = (error - self.prev_error) / dt
        self.prev_error = error
        output = self.kp * error + self.ki * self.integral + self.kd * derivative
        return max(self.output_min, min(self.output_max, output))


# ============================================================
# 编队控制器 (领航-跟随模式)
# ============================================================
class FormationController:
    """
    领航-跟随编队控制器
    - 使用 best.onnx 检测领航车
    - PID 控制速度（距离）和转向（角度）
    - 优先 ROS /cmd_vel，回退 TCP 协议
    """

    def __init__(self):
        self.model_path = CAR_MODEL_PATH
        self.session = None
        self.enabled = False
        self.detect_only = False  # 仅检测模式，不发送指令

        # ---- 检测参数 ----
        self.confidence_threshold = 0.5
        self.iou_threshold = 0.45
        self.input_size = (640, 640)

        # ---- PID 控制器 ----
        # speed_pid: distance_error -> linear.x
        self.speed_pid = VelocityPID(
            kp=0.8, ki=0.05, kd=0.1,
            output_min=-0.3, output_max=0.8,
        )
        # steer_pid: lateral_error -> angular.z
        self.steer_pid = VelocityPID(
            kp=1.2, ki=0.02, kd=0.3,
            output_min=-0.8, output_max=0.8,
        )

        # ---- 目标参数 ----
        self.target_bbox_height = 200.0   # 目标 bbox 高度(px)，对应约 1m
        self.target_center_x = 320.0      # 图像中心 x (640/2)

        # ---- 帧跳过 ----
        self.frame_skip = 3               # 每 3 帧推理一次
        self.frame_count = 0

        # ---- 丢失追踪 ----
        self.max_lost_frames = 5
        self.lost_frames = 0
        self.latest_detection: Optional[Dict] = None

        # ---- 当前控制输出 ----
        self.cmd_linear = 0.0
        self.cmd_angular = 0.0
        self.prev_time = time.time()

        # ---- ROS 发布器 ----
        self.pub_cmd_vel = None

        self._load_model()
        self._init_ros()

    # -------- 模型加载 --------
    def _load_model(self):
        if not ORT_AVAILABLE:
            print("[Formation] onnxruntime 未安装")
            return
        if not os.path.exists(self.model_path):
            print(f"[Formation] 模型文件不存在: {self.model_path}")
            return
        try:
            self.session = ort.InferenceSession(
                self.model_path,
                providers=['CPUExecutionProvider'],
            )
            print(f"[Formation] ONNX 模型加载完成: {self.model_path}")
        except Exception as e:
            print(f"[Formation] ONNX 模型加载失败: {e}")
            self.session = None

    def _init_ros(self):
        if not ROS_AVAILABLE:
            print("[Formation] ROS 不可用，将使用 TCP (端口 6000) 发送控制指令")
            return
        try:
            # 避免重复 init_node
            try:
                rospy.get_node_uri()
            except Exception:
                rospy.init_node("formation_controller", anonymous=True,
                               disable_signals=True)
            self.pub_cmd_vel = rospy.Publisher("/cmd_vel", Twist, queue_size=10)
            print("[Formation] ROS 发布器就绪 -> /cmd_vel")
        except Exception as e:
            print(f"[Formation] ROS 初始化失败: {e}，回退 TCP")

    # -------- 推理管线 --------
    def _preprocess(self, frame: np.ndarray) -> np.ndarray:
        """BGR -> RGB, resize 640x640, normalize [0,1], HWC -> CHW, add batch"""
        img = cv2.resize(frame, self.input_size)
        img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
        img = img.astype(np.float32) / 255.0
        img = np.transpose(img, (2, 0, 1))          # HWC -> CHW
        img = np.expand_dims(img, axis=0)            # (1, 3, 640, 640)
        return img

    def _postprocess(self, outputs, frame_w: int, frame_h: int) -> List[Dict]:
        """
        解析 YOLO 输出 (1, 25200, 6) -> [cx, cy, w, h, conf, class]
        返回检测列表，坐标归一化到 0-1 范围
        """
        detections = outputs[0][0]  # (25200, 6)

        # 置信度筛选
        mask = detections[:, 4] > self.confidence_threshold
        detections = detections[mask]
        if len(detections) == 0:
            return []

        boxes = []
        scores = []
        for det in detections:
            cx, cy, w, h = det[0], det[1], det[2], det[3]
            x1 = cx - w / 2.0
            y1 = cy - h / 2.0
            x2 = cx + w / 2.0
            y2 = cy + h / 2.0
            boxes.append([x1, y1, x2, y2])
            scores.append(float(det[4]))

        boxes_np = np.array(boxes, dtype=np.float32)
        scores_np = np.array(scores, dtype=np.float32)

        # NMS
        if len(boxes_np) == 0:
            return []

        indices = cv2.dnn.NMSBoxes(
            boxes_np.tolist(), scores_np.tolist(),
            self.confidence_threshold, self.iou_threshold,
        )

        results = []
        if len(indices) > 0:
            for i in indices.flatten():
                bx = boxes_np[int(i)]
                pw = bx[2] - bx[0]
                ph = bx[3] - bx[1]
                results.append({
                    "bbox": bx.tolist(),
                    "center_x": float(bx[0] + bx[2]) / 2.0,
                    "center_y": float(bx[1] + bx[3]) / 2.0,
                    "width": float(pw),
                    "height": float(ph),
                    "confidence": float(scores_np[int(i)]),
                })
        return results

    def _select_target(self, detections: List[Dict]) -> Optional[Dict]:
        """选择最佳检测作为领航车：面积 × 置信度 最大"""
        if not detections:
            return None
        # 优先面积大 + 置信度高
        return max(detections,
                   key=lambda d: d["width"] * d["height"] * d["confidence"])

    # -------- 控制指令发送 --------
    def _send_command_ros(self, linear_x: float, angular_z: float) -> bool:
        if not ROS_AVAILABLE or self.pub_cmd_vel is None:
            return False
        try:
            t = Twist()
            t.linear.x = linear_x
            t.angular.z = angular_z
            self.pub_cmd_vel.publish(t)
            return True
        except Exception as e:
            print(f"[Formation] ROS 发送失败: {e}")
            return False

    def _send_command_tcp(self, linear_x: float, angular_z: float) -> bool:
        """通过 TCP hex 协议发送自由控制指令 (cmd=0x10)"""
        try:
            def to_signed_byte(val: float) -> int:
                """映射 -1.0~1.0 到 -100~100"""
                v = int(round(max(-100.0, min(100.0, val * 100.0))))
                return v & 0xFF

            sx = to_signed_byte(linear_x)
            sy = to_signed_byte(angular_z)
            data = f"{sx:02X}{sy:02X}"
            content = "011002" + data       # vehicle=01, cmd=0x10, len=2
            csum = sum(int(content[i:i+2], 16) for i in range(0, len(content), 2)) % 256
            frame = f"${content}{csum:02X}#"

            with socket.create_connection(("127.0.0.1", 6000), timeout=0.5) as sock:
                sock.sendall(frame.encode())
            return True
        except Exception as e:
            print(f"[Formation] TCP 发送失败: {e}")
            return False

    def _send_command(self, linear_x: float, angular_z: float):
        """发送控制指令: 优先 ROS，回退 TCP"""
        self.cmd_linear = linear_x
        self.cmd_angular = angular_z
        if not self._send_command_ros(linear_x, angular_z):
            self._send_command_tcp(linear_x, angular_z)

    # -------- STOP 指令 --------
    def _send_stop(self):
        """急停"""
        self._send_command(0.0, 0.0)

    # -------- 主更新循环 --------
    def update(self, frame: np.ndarray) -> Dict:
        """每帧调用：推理 → 选目标 → PID → 发送指令"""
        if self.session is None:
            return {"status": "model_error", "cmd": {"linear": 0.0, "angular": 0.0}}

        now = time.time()
        dt = now - self.prev_time
        if dt <= 0:
            dt = 0.05
        self.prev_time = now

        # ---- 帧跳过：非推理帧复用上次检测 ----
        self.frame_count += 1
        skip_inference = (self.frame_count % self.frame_skip != 0)

        if skip_inference:
            if self.latest_detection is not None:
                return self._control(self.latest_detection, dt)
            return {"status": "skipped",
                    "cmd": {"linear": self.cmd_linear, "angular": self.cmd_angular}}

        # ---- 推理 ----
        try:
            input_tensor = self._preprocess(frame)
            outputs = self.session.run(None, {"images": input_tensor})
        except Exception as e:
            print(f"[Formation] 推理失败: {e}")
            return {"status": "inference_error",
                    "cmd": {"linear": self.cmd_linear, "angular": self.cmd_angular}}

        detections = self._postprocess(outputs, frame.shape[1], frame.shape[0])
        target = self._select_target(detections)

        # ---- 丢失处理 ----
        if target is None:
            self.lost_frames += 1
            if self.lost_frames >= self.max_lost_frames:
                if not self.detect_only:
                    self._send_stop()
                self.speed_pid.reset()
                self.steer_pid.reset()
            self.latest_detection = None
            return {"status": "no_target", "lost_frames": self.lost_frames,
                    "cmd": {"linear": self.cmd_linear, "angular": self.cmd_angular}}

        self.lost_frames = 0
        self.latest_detection = target
        return self._control(target, dt)

    def _control(self, target: Dict, dt: float) -> Dict:
        """根据检测结果计算 PID 输出并发送指令"""
        # ---- 横向误差（归一化到 -1~1）----
        lateral_error = (target["center_x"] - self.target_center_x) / self.target_center_x

        # ---- 距离误差（基于 bbox 高度）----
        actual_height = target["height"]
        distance_error = self.target_bbox_height - actual_height
        # 正值 = 太远（需加速），负值 = 太近（需减速）

        # ---- PID ----
        # 转向：负号 = 目标在右侧时向右转
        angular = -self.steer_pid.update(lateral_error, dt)
        # 速度：正误差（太远）→ 加速
        linear = self.speed_pid.update(distance_error, dt)

        # ---- 死角 ----
        if abs(lateral_error) < 0.03:
            angular = 0.0
        if abs(distance_error) < 15.0:
            linear = 0.0

        # ---- 发送（detect_only 模式跳过）----
        if not self.detect_only:
            self._send_command(linear, angular)

        return {
            "status": "tracking",
            "detection": {
                "bbox": target["bbox"],
                "confidence": target["confidence"],
                "height": round(actual_height, 4),
            },
            "pid": {
                "lateral_error": round(lateral_error, 3),
                "distance_error": round(distance_error, 1),
            },
            "cmd": {"linear": round(linear, 3), "angular": round(angular, 3)},
        }


    # -------- 控制接口 --------
    def detect(self):
        """启动仅检测模式（不发指令），用于发现领航车后弹窗确认"""
        self.enabled = True
        self.detect_only = True
        self.lost_frames = 0
        self.speed_pid.reset()
        self.steer_pid.reset()
        self.prev_time = time.time()
        self.frame_count = 0
        self.cmd_linear = 0.0
        self.cmd_angular = 0.0
        return {"status": "detecting"}

    # -------- 控制接口 --------
    def start(self) -> Dict:
        self.enabled = True
        self.detect_only = False
        self.lost_frames = 0
        self.speed_pid.reset()
        self.steer_pid.reset()
        self.prev_time = time.time()
        self.frame_count = 0
        return {"status": "formation_started"}

    def stop(self) -> Dict:
        self.enabled = False
        self._send_stop()
        self.latest_detection = None
        return {"status": "formation_stopped"}

    def get_status(self) -> Dict:
        target_info = None
        if self.latest_detection:
            target_info = {
                "bbox": self.latest_detection["bbox"],
                "confidence": self.latest_detection["confidence"],
            }
        return {
            "enabled": self.enabled,
            "detect_only": self.detect_only,
            "model_loaded": self.session is not None,
            "ros_available": ROS_AVAILABLE,
            "control_mode": "ros" if (ROS_AVAILABLE and self.pub_cmd_vel is not None) else "tcp",
            "target": target_info,
            "cmd": {"linear": round(self.cmd_linear, 3), "angular": round(self.cmd_angular, 3)},
            "lost_frames": self.lost_frames,
            "config": {
                "confidence_threshold": self.confidence_threshold,
                "target_bbox_height": self.target_bbox_height,
                "speed_kp": self.speed_pid.kp,
                "speed_ki": self.speed_pid.ki,
                "speed_kd": self.speed_pid.kd,
                "steer_kp": self.steer_pid.kp,
                "steer_ki": self.steer_pid.ki,
                "steer_kd": self.steer_pid.kd,
                "max_lost_frames": self.max_lost_frames,
                "frame_skip": self.frame_skip,
            },
        }

    def set_config(self, config: Dict) -> Dict:
        for key, value in config.items():
            if key == "confidence_threshold":
                self.confidence_threshold = float(value)
            elif key == "target_bbox_height":
                self.target_bbox_height = float(value)
            elif key == "speed_kp":
                self.speed_pid.kp = float(value)
            elif key == "speed_ki":
                self.speed_pid.ki = float(value)
            elif key == "speed_kd":
                self.speed_pid.kd = float(value)
            elif key == "steer_kp":
                self.steer_pid.kp = float(value)
            elif key == "steer_ki":
                self.steer_pid.ki = float(value)
            elif key == "steer_kd":
                self.steer_pid.kd = float(value)
            elif key == "max_lost_frames":
                self.max_lost_frames = int(value)
            elif key == "frame_skip":
                self.frame_skip = int(value)
        return {"status": "config_updated", "config": self.get_status()["config"]}


# ============================================================
# 智能监控服务
# ============================================================
class IntelligentMonitorService:
    def __init__(self):
        self.face_detector_net = None
        self.face_recognition_net = None
        self.person_detector_net = None
        self.yolo_model = None

        self.face_enabled = False
        self.yolo_enabled = False
        self.fall_enabled = False
        self.formation_enabled = False
        self.running = False
        self.thread = None
        self.capture = None
        self.lock = threading.Lock()

        self.known_faces: List[Dict] = []
        self.latest_result = {
            "face": {"status": "idle", "name": "unknown"},
            "yolo": {"enabled": False, "people": []},
            "fall": {"enabled": False, "status": "idle", "confidence": 0.0},
            "formation": {"enabled": False, "status": "idle"},
            "timestamp": None,
        }

        self.fall_history: List[Dict] = []
        self.fall_counter = 0
        self.previous_person = None

        self.face_threshold = 0.8
        self.detector_confidence = 0.7

        # 编队控制器
        self.formation_controller = FormationController()

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

    CAMERA_STREAM_URL = "http://127.0.0.1:6500/video_feed"

    def _open_camera(self):
        """打开摄像头：优先从本地 MJPEG 流读取（避免与 6500 视频推流冲突），回退到直连摄像头"""
        cap = cv2.VideoCapture(self.CAMERA_STREAM_URL)
        if not cap.isOpened():
            print(f"[WARN] 无法从流读取摄像头 ({self.CAMERA_STREAM_URL})，尝试直连 /dev/video0")
            cap = cv2.VideoCapture(0)
        return cap

    def register_face(self, name: str, sample_count: int = 5) -> Dict:
        if not name or not name.strip():
            return {"status": "error", "message": "姓名不能为空"}
        cap = self._open_camera()
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
        self.capture = self._open_camera()
        if not self.capture.isOpened():
            with self.lock:
                self.latest_result = {
                    "face": {"status": "camera_error", "name": "unknown"},
                    "yolo": {"enabled": self.yolo_enabled, "people": []},
                    "fall": {"enabled": self.fall_enabled, "status": "camera_error", "confidence": 0.0},
                    "formation": {"enabled": self.formation_enabled, "status": "camera_error"},
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

            # ---- 编队控制 ----
            formation_result = {"enabled": self.formation_enabled, "status": "formation_disabled"}
            if self.formation_enabled:
                formation_result = self.formation_controller.update(frame)

            with self.lock:
                self.latest_result = {
                    "face": face_result,
                    "yolo": yolo_result,
                    "fall": fall_result,
                    "formation": formation_result,
                    "timestamp": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime()),
                }
            time.sleep(0.05)

        if self.capture is not None:
            self.capture.release()
            self.capture = None

        with self.lock:
            self.latest_result["face"] = {"status": "stopped", "name": "unknown"}
            self.latest_result["formation"] = {"enabled": False, "status": "stopped"}

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
        # 停止编队时急停
        self.formation_controller._send_stop()
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

    # ---- 编队控制 ----
    def enable_formation(self) -> Dict:
        self.formation_enabled = True
        return self.formation_controller.start()

    def disable_formation(self) -> Dict:
        self.formation_enabled = False
        return self.formation_controller.stop()

    def formation_config(self, config: Dict) -> Dict:
        return self.formation_controller.set_config(config)

    def get_status(self) -> Dict:
        with self.lock:
            return {
                "running": self.running,
                "face_enabled": self.face_enabled,
                "yolo_enabled": self.yolo_enabled,
                "fall_enabled": self.fall_enabled,
                "formation_enabled": self.formation_enabled,
                "known_faces": [item.get("name") for item in self.known_faces],
                "latest_result": self.latest_result,
                "formation": self.formation_controller.get_status(),
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


# ============================================================
# 编队控制 API
# ============================================================
@app.route("/formation/detect", methods=["POST"])
def api_formation_detect():
    """启动仅检测模式（不发指令）"""
    return jsonify(service.formation_controller.detect())


@app.route("/formation/start", methods=["POST"])
def api_formation_start():
    """启动编队跟随"""
    return jsonify(service.enable_formation())


@app.route("/formation/stop", methods=["POST"])
def api_formation_stop():
    """停止编队跟随（急停）"""
    return jsonify(service.disable_formation())


@app.route("/formation/status", methods=["GET"])
def api_formation_status():
    """获取编队控制状态"""
    return jsonify(service.formation_controller.get_status())


@app.route("/formation/config", methods=["POST"])
def api_formation_config():
    """
    设置编队参数
    JSON body 示例:
    {
        "confidence_threshold": 0.5,
        "target_bbox_height": 200,
        "speed_kp": 0.8,
        "speed_ki": 0.05,
        "speed_kd": 0.1,
        "steer_kp": 1.2,
        "steer_ki": 0.02,
        "steer_kd": 0.3,
        "max_lost_frames": 5,
        "frame_skip": 3
    }
    """
    payload = request.get_json(silent=True) or {}
    return jsonify(service.formation_config(payload))


if __name__ == "__main__":
    print("启动统一智能监控服务，监听 0.0.0.0:5001")
    print("  编队控制 API: /formation/start /formation/stop /formation/status /formation/config")
    app.run(host="0.0.0.0", port=5001, debug=False)
