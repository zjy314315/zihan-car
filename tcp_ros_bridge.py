#!/usr/bin/env python3
"""
HarmonyOS App <-> ROS TCP Bridge
监听 6000 端口，接收 App 发送的十六进制指令，转发到 ROS

协议格式: $01 TYPE SIZE DATA CHECKSUM#
    例: $0115020103#
    - $ : 开始符
    - 01: 车辆类型(保留)
    - 15: 命令标记(按钮控制)
    - 02: 数据长度
    - 01: 数据(前进)
    - 03: 校验和
    - # : 结束符
"""

import socket
import json
import subprocess
import tempfile
import urllib.request
import threading
import sys
import os
import signal

from zihan_car_integration.process_lifecycle import ProjectProcessManager

# ============================================================
# ROS 导入 (如果环境没有 ROS, 可以设置 USE_ROS=False 进行调试)
# ============================================================
USE_ROS = True
try:
    import rospy
    from geometry_msgs.msg import Twist, TwistStamped
    from std_msgs.msg import String, Float32, Int32, Bool
except ImportError:
    USE_ROS = False
    print("[WARN] rospy 未安装，将以调试模式运行（仅打印日志）")


class TcpRosBridge:
    """TCP 转 ROS 桥接服务器"""

    # 方向映射表: cmd=15 按钮控制
    DIRECTION_MAP = {
        0: "停车",
        1: "前进",
        2: "后退",
        3: "左平移",
        4: "右平移",
        5: "左旋转",
        6: "右旋转",
        7: "刹车停止",
    }

    def __init__(self, host="0.0.0.0", port=6000):
        self.host = host
        self.port = port
        self.server_socket = None
        self.running = False
        self.audio_lock = threading.Lock()
        self.lifecycle = ProjectProcessManager()
        self.dialogue_enabled = False

        # ROS 发布器 (在 init_ros 中初始化)
        self.pub_cmd_vel = None
        self.pub_cmd_debug = None
        self.pub_buzzer = None
        self.pub_tracking = None
        self.pub_camera_switch = None

    def init_ros(self):
        """初始化 ROS 节点和发布器"""
        if not USE_ROS:
            return

        rospy.init_node("tcp_ros_bridge", anonymous=True)

        # ---- 发布器 ----
        # 速度控制 /cmd_vel (Twist)
        self.pub_cmd_vel = rospy.Publisher("/cmd_vel", Twist, queue_size=10)

        # 调试/原始数据
        self.pub_cmd_debug = rospy.Publisher("/app_command", String, queue_size=10)

        # 蜂鸣器
        self.pub_buzzer = rospy.Publisher("/buzzer", Bool, queue_size=10)

        # 巡线/循迹开关
        self.pub_tracking = rospy.Publisher("/tracking_enabled", Bool, queue_size=10)

        # 摄像头切换
        self.pub_camera_switch = rospy.Publisher("/camera_switch", Int32, queue_size=10)

        rospy.loginfo("ROS 节点初始化完成")
        print("[ROS] 节点初始化完成")

    def start(self):
        """启动 TCP 服务器"""
        self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.server_socket.bind((self.host, self.port))
        self.server_socket.listen(5)
        self.running = True

        print(f"[Server] TCP 服务器已启动: {self.host}:{self.port}")
        print(f"[Server] 等待 App 连接...")

        while self.running:
            try:
                client_sock, addr = self.server_socket.accept()
                print(f"[Server] 收到连接: {addr[0]}:{addr[1]}")
                handler = threading.Thread(
                    target=self.handle_client,
                    args=(client_sock, addr),
                    daemon=True,
                )
                handler.start()
            except OSError:
                break

    def stop(self):
        """停止服务器"""
        self.running = False
        if self.server_socket:
            self.server_socket.close()
        try:
            result = self.lifecycle.stop_all()
            print(f"[PROC] stop_all: {result}")
        except Exception as error:
            print(f"[PROC] stop_all failed: {error}")
        print("[Server] 服务器已停止")

    def answer_app_question(self, question):
        payload = {
            "model": "qwen2.5:0.5b",
            "stream": False,
            "options": {"num_predict": 32, "temperature": 0.2},
            "messages": [
                {"role": "system", "content": "You are Zihan's car. Reply in Chinese using at most 20 characters."},
                {"role": "user", "content": question},
            ],
        }
        request = urllib.request.Request(
            "http://127.0.0.1:11434/api/chat",
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
        )
        with urllib.request.urlopen(request, timeout=90) as response:
            answer = json.loads(response.read().decode("utf-8"))["message"]["content"]
        return "".join(answer.split())[:20] or "\\u6211\\u6682\\u65f6\\u65e0\\u6cd5\\u56de\\u7b54\\u3002"

    def speak_app_answer(self, answer):
        with self.audio_lock:
            self._speak_app_answer(answer)

    def _speak_app_answer(self, answer):
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as audio:
            audio_path = audio.name
        try:
            subprocess.run(["espeak-ng", "-v", "zh", "-s", "155", "-w", audio_path, answer], check=True)
            os.chmod(audio_path, 0o644)

            # Ensure the USB speaker is not muted before every LLM reply.
            subprocess.run(["amixer", "-c", "0", "sset", "PCM", "30"], check=False)

            try:
                # This path has been verified on the Jetson car.
                subprocess.run(["aplay", "-D", "plughw:0,0", audio_path], check=True)
            except (OSError, subprocess.CalledProcessError):
                subprocess.run([
                    "runuser", "-u", "jetson", "--", "env",
                    "XDG_RUNTIME_DIR=/run/user/1000",
                    "PULSE_SERVER=unix:/run/user/1000/pulse/native",
                    "paplay",
                    "--device=alsa_output.usb-C-Media_Electronics_Inc._USB_Audio_Device-00.analog-stereo",
                    audio_path,
                ], check=True)
        finally:
            if os.path.exists(audio_path):
                os.unlink(audio_path)
    def process_app_question(self, line):
        try:
            if not self.dialogue_enabled:
                print("[APP] ignored LLM question because dialogue page is not active")
                return
            question = json.loads(line[len("@LLM:"):]).get("question", "").strip()
            if not question:
                return
            print(f"[APP] question: {question}")
            answer = self.answer_app_question(question)
            print(f"[APP] answer: {answer}")
            self.speak_app_answer(answer)
        except Exception as error:
            print(f"[APP] LLM request failed: {error}")
    def process_lifecycle_command(self, line, client_sock=None):
        try:
            payload = json.loads(line[len("@PROC:"):])
            action = str(payload.get("action", "")).strip().lower()
            feature = str(payload.get("feature", "")).strip().lower()
            result = self.lifecycle.handle(action, feature)
            if action == "stop_all":
                self.dialogue_enabled = False
            if feature == "dialogue":
                if action == "start" and result.get("ok"):
                    self.dialogue_enabled = True
                elif action == "stop":
                    self.dialogue_enabled = False
            print(f"[PROC] {action} {feature}: {result}")
            if client_sock:
                try:
                    client_sock.sendall((json.dumps(result, ensure_ascii=False) + "\n").encode("utf-8"))
                except OSError:
                    pass
        except Exception as error:
            print(f"[PROC] lifecycle command failed: {error}")
    def handle_client(self, client_sock, addr):
        """处理单个客户端连接"""
        buffer = ""
        try:
            while self.running:
                data = client_sock.recv(1024)
                if not data:
                    print(f"[Client] 客户端断开: {addr[0]}:{addr[1]}")
                    break

                buffer += data.decode("utf-8", errors="ignore")

                while buffer.startswith("@PROC:") and "\n" in buffer:
                    line, buffer = buffer.split("\n", 1)
                    self.process_lifecycle_command(line, client_sock)

                while buffer.startswith("@LLM:") and "\n" in buffer:
                    line, buffer = buffer.split("\n", 1)
                    self.process_app_question(line)

                # 按完整帧解析 ($ ... #)
                while "$" in buffer and "#" in buffer:
                    start = buffer.index("$")
                    end = buffer.index("#", start)
                    frame = buffer[start : end + 1]
                    buffer = buffer[end + 1 :]

                    self.process_frame(frame, addr)

        except ConnectionResetError:
            print(f"[Client] 连接重置: {addr[0]}:{addr[1]}")
        except Exception as e:
            print(f"[Client] 错误: {e}")
        finally:
            client_sock.close()

    def process_frame(self, frame, addr):
        """
        解析并处理一帧数据
        格式: $01 TYPE SIZE DATA CHECKSUM#
        """
        print(f"[RECV] <{addr[0]}> {frame}")

        if not frame.startswith("$") or not frame.endswith("#"):
            print(f"[ERR] 帧格式错误: {frame}")
            return

        content = frame[1:-1]  # 去掉 $ 和 #

        # 最小长度: 01(类型) + 02(标记) + 02(长度) + 02(校验) = 8
        if len(content) < 8 or len(content) % 2 != 0:
            print(f"[ERR] 帧长度错误: {content}")
            return

        vehicle_type = content[0:2]  # 保留: 01
        cmd_type = content[2:4]      # 命令标记
        data_len_hex = content[4:6]  # 数据长度(十六进制)
        data_start = 6
        data_end = len(content) - 2
        data_hex = content[data_start:data_end]  # 数据主体
        checksum_hex = content[data_end:]        # 校验和

        # 校验
        expected_checksum = self.calc_checksum(content[:-2])
        actual_checksum = int(checksum_hex, 16)
        if expected_checksum != actual_checksum:
            print(f"[ERR] 校验和不匹配: 期望={expected_checksum:02X}, 实际={checksum_hex}")
            return

        # 发布原始命令到 ROS (调试用)
        if USE_ROS and self.pub_cmd_debug:
            self.pub_cmd_debug.publish(frame)

        # 按命令类型分发
        self.dispatch_command(cmd_type, data_hex, data_len_hex)

    def dispatch_command(self, cmd_type, data_hex, data_len_hex):
        """根据命令类型分发处理"""
        cmd = int(cmd_type, 16)
        data_len = int(data_len_hex, 16) if data_len_hex else 0

        if cmd == 0x0F:
            # 进入界面 - 上报当前页面
            page = data_hex if data_hex else "00"
            print(f"[CMD] 进入界面: 页面={page}")

        elif cmd == 0x01:
            # 获取硬件版本号
            print(f"[CMD] 获取硬件版本号")
            # 可以回复硬件版本

        elif cmd == 0x02:
            # 获取电池电压
            print(f"[CMD] 获取电池电压")

        elif cmd == 0x10:
            # 自由控制小车 (cmd_vel)
            self.handle_car_control(data_hex)

        elif cmd == 0x11:
            # 控制 PWM 舵机
            self.handle_pwm_servo(data_hex)

        elif cmd == 0x12:
            # 控制机械臂
            print(f"[CMD] 控制机械臂: data={data_hex}")

        elif cmd == 0x13:
            # 设置蜂鸣器
            self.handle_buzzer(data_hex)

        elif cmd == 0x15:
            # 按钮控制小车
            self.handle_button_control(data_hex)

        elif cmd == 0x16:
            # 控制速度
            print(f"[CMD] 控制速度: data={data_hex}")

        elif cmd == 0x17:
            # 自稳开关
            print(f"[CMD] 自稳开关: data={data_hex}")

        elif cmd == 0x18:
            # 摄像头切换
            self.handle_camera_switch(data_hex)

        elif cmd == 0x20:
            # 麦克纳姆轮控制
            print(f"[CMD] 麦克纳姆轮控制: data={data_hex}")

        elif cmd == 0x21:
            # 四轮独立更新速度
            self.handle_four_wheel_speed(data_hex)

        elif cmd == 0x30:
            # 彩色灯带颜色
            print(f"[CMD] 灯带颜色: data={data_hex}")

        elif cmd == 0x31:
            # 彩色灯带特效
            print(f"[CMD] 灯带特效: data={data_hex}")

        elif cmd == 0x32:
            # 彩色灯带呼吸灯
            print(f"[CMD] 灯带呼吸效果: data={data_hex}")

        elif cmd == 0x3C:
            # 超声波测距
            print(f"[CMD] 超声波测距: data={data_hex}")

        elif cmd == 0x63:
            # 开启循迹/巡航
            self.handle_tracking(True)

        elif cmd == 0x64:
            # 关闭循迹/巡航
            self.handle_tracking(False)

        elif cmd in (0x60, 0x61, 0x62):
            actions = {0x60: "拍照", 0x61: "开始录像", 0x62: "结束录像"}
            print(f"[CMD] {actions[cmd]}")

        else:
            print(f"[CMD] 未知命令: cmd=0x{cmd_type}, data={data_hex}")

    def handle_car_control(self, data_hex):
        """cmd=0x10: 自由控制小车 -> /cmd_vel"""
        if len(data_hex) < 4:
            print(f"[ERR] car_control 数据长度不足: {data_hex}")
            return

        raw_x = int(data_hex[0:2], 16)
        raw_y = int(data_hex[2:4], 16)

        # 解码: if (v >= 128) v -= 256
        speed_x = raw_x if raw_x < 128 else raw_x - 256
        speed_y = raw_y if raw_y < 128 else raw_y - 256

        # 映射 -100~100 到线速度和角速度
        linear_x = speed_x / 100.0
        angular_z = speed_y / 100.0

        print(f"[CMD] 自由控制: x={speed_x}, y={speed_y} "
              f"-> linear={linear_x:.2f}, angular={angular_z:.2f}")

        if USE_ROS and self.pub_cmd_vel:
            twist = Twist()
            twist.linear.x = linear_x
            twist.angular.z = angular_z
            self.pub_cmd_vel.publish(twist)

    def handle_button_control(self, data_hex):
        """cmd=0x15: 按钮控制小车 -> /cmd_vel"""
        if len(data_hex) < 2:
            print(f"[ERR] button_control 数据长度不足: {data_hex}")
            return

        direction = int(data_hex[0:2], 16)
        dir_name = self.DIRECTION_MAP.get(direction, f"未知({direction})")
        print(f"[CMD] 按钮控制: {dir_name}")

        # 方向 -> Twist
        twist = Twist()
        if direction == 0:  # 停车
            pass  # 全零
        elif direction == 1:  # 前进
            twist.linear.x = 0.5
        elif direction == 2:  # 后退
            twist.linear.x = -0.5
        elif direction == 3:  # 左平移
            twist.linear.y = 0.5
        elif direction == 4:  # 右平移
            twist.linear.y = -0.5
        elif direction == 5:  # 左旋转
            twist.angular.z = 0.5
        elif direction == 6:  # 右旋转
            twist.angular.z = -0.5
        elif direction == 7:  # 刹车停止
            pass  # 全零急停

        if USE_ROS and self.pub_cmd_vel:
            self.pub_cmd_vel.publish(twist)

    def handle_four_wheel_speed(self, data_hex):
        """cmd=0x21: 四轮独立速度"""
        if len(data_hex) < 8:
            print(f"[ERR] four_wheel 数据长度不足: {data_hex}")
            return

        speeds = []
        for i in range(4):
            raw = int(data_hex[i*2:(i+1)*2], 16)
            speed = raw if raw < 128 else raw - 256
            speeds.append(speed)

        print(f"[CMD] 四轮速度: FL={speeds[0]}, RL={speeds[1]}, "
              f"FR={speeds[2]}, RR={speeds[3]}")

        # 可发布到单独的车轮 topic
        # if USE_ROS:
        #     ...

    def handle_pwm_servo(self, data_hex):
        """cmd=0x11: PWM 舵机控制"""
        if len(data_hex) < 4:
            return
        channel = int(data_hex[0:2], 16)
        angle = int(data_hex[2:4], 16)
        print(f"[CMD] 舵机: channel={channel}, angle={angle}")

    def handle_buzzer(self, data_hex):
        """cmd=0x13: 蜂鸣器"""
        if not data_hex:
            return
        on = int(data_hex[0:2], 16) != 0
        print(f"[CMD] 蜂鸣器: {'ON' if on else 'OFF'}")
        if USE_ROS and self.pub_buzzer:
            self.pub_buzzer.publish(Bool(data=on))

    def handle_tracking(self, enabled):
        """cmd=0x63/0x64: 循迹开关"""
        status = "开启" if enabled else "关闭"
        print(f"[CMD] 循迹: {status}")
        if USE_ROS and self.pub_tracking:
            self.pub_tracking.publish(Bool(data=enabled))

    def handle_camera_switch(self, data_hex):
        """cmd=0x18: 摄像头切换"""
        if not data_hex:
            return
        cam_id = int(data_hex[0:2], 16)
        print(f"[CMD] 摄像头切换: {cam_id}")
        if USE_ROS and self.pub_camera_switch:
            self.pub_camera_switch.publish(Int32(data=cam_id))

    @staticmethod
    def calc_checksum(hex_str):
        """计算校验和: 所有字节之和 % 256"""
        total = 0
        for i in range(0, len(hex_str), 2):
            byte_val = int(hex_str[i:i+2], 16)
            total = (total + byte_val) % 256
        return total


def signal_handler(sig, frame):
    print("\n[退出] 收到停止信号")
    bridge.stop()
    sys.exit(0)


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 6000

    bridge = TcpRosBridge(port=port)

    if USE_ROS:
        bridge.init_ros()

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    print("=" * 50)
    print("  HarmonyOS App <-> ROS TCP Bridge")
    print(f"  监听端口: {port}")
    print(f"  ROS 模式: {'启用' if USE_ROS else '禁用(调试)'}")
    print("=" * 50)

    bridge.start()