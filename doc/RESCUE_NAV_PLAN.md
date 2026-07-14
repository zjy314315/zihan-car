# 智能小车 — 多点导航 + 紧急救援 实施方案（修订版）

> 日期: 2026-07-12
> 系统: Ubuntu 20.04.6 ROS2 Foxy (Jetson Nano / rose2)
> 硬件: rose2 (Rockchip ARM64), STM32/AT32 底盘(固件不可修改)
> 项目路径: `C:\Users\21774\Desktop\oh-ai-car-ros-app`
> 代码备份: `C:\Users\21774\Desktop\car\`

---

## 一、需求总览

| # | 需求 | 说明 | 优先级 | 依赖 |
|---|------|------|--------|------|
| 1 | **多点导航** | A→B→C→D... 任意顺序航点导航 | P0 | 底盘控制API |
| 2 | **紧急救援** | 人脸触发 → 手机GPS → 导航前往 → 返航 | P1 | 多点导航 |

---

## 二、现有系统真实架构（勘误）

### 2.1 实际架构图

之前我假设了 Nav2 已安装且通过 ROS2 topic 控制，**实际完全不是这样**：

```
┌─────────────────────────────────────────────────────────────────┐
│                     鸿蒙 App (HarmonyOS)                         │
│  TCP:6000 ──→ $01 TYP SIZE DATA CHECKSUM#                       │
│  HTTP:5001 ──→ 人脸识别服务 (port 5001)                          │
└──────────────────────────┬──────────────────────────────────────┘
                           │ WiFi TCP
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│              Jetson Nano / rose2 (192.168.x.x)                   │
│                                                                  │
│  ┌──────────────────────────────────────────────────┐           │
│  │         Rosmaster-App (Flask, port 6500)          │           │
│  │  ┌──────────────────────────────────────────┐    │           │
│  │  │  TCP 服务器 (port 6000)                   │    │           │
│  │  │  接收 $01... 协议命令 → 解析 → 执行        │    │           │
│  │  │  核心逻辑: rosmaster_main.so (编译的C库)    │    │           │
│  │  └──────────────┬───────────────────────────┘    │           │
│  │                 │                                │           │
│  │  ┌──────────────▼───────────────────────────┐    │           │
│  │  │  Rosmaster_Lib (Python, 串口通信)          │    │           │
│  │  │  协议: 0xFF 0xFC ... → /dev/myserial       │    │           │
│  │  │  方法: set_car_run, set_car_motion, ...    │    │           │
│  │  └──────────────┬───────────────────────────┘    │           │
│  └─────────────────┼────────────────────────────────┘           │
│                    │ USB/UART                                   │
│  ┌─────────────────▼────────────────────────────────────────┐  │
│  │           STM32/AT32 底盘 (固件不可修改)                   │  │
│  │  电机驱动 | 编码器 | IMU | 舵机 | 蜂鸣器 | 灯带            │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌──────────────────────────────────────────────────────┐       │
│  │      ROS2 Foxy (几乎未使用)                          │       │
│  │  仅运行: /parameter_events, /rosout                  │       │
│  │  ❌ Nav2 未安装 | ❌ 无导航栈 | ❌ 无SLAM             │       │
│  │                                                      │       │
│  │  car_follower 包: follower_node.py (YOLO人物跟踪)    │       │
│  │  订阅: /camera/image_raw → 发布: /cmd_vel           │       │
│  └──────────────────────────────────────────────────────┘       │
│                                                                  │
│  ┌──────────────────────────────────────────────────────┐       │
│  │       rosboard/ 工具集                               │       │
│  │  laser_Avoidance_a1_X3.py  — 激光雷达避障            │       │
│  │  findObj.py                  — 目标检测              │       │
│  │  trackObj.py                 — 目标跟踪              │       │
│  └──────────────────────────────────────────────────────┘       │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 关键发现

| 我原来假设的 | 实际发现的 |
|-------------|-----------|
| Nav2 已安装使用 | ❌ **未安装 Nav2**，ROS2 几乎空闲 |
| 控制通过 ROS topic `/cmd_vel` | ❌ 通过 **Rosmaster_Lib 串口协议**直接控制 STM32 |
| `tcp_ros_bridge.py` 在运行 | ❌ 小车自己有 TCP 服务器，桌面上的桥接未部署 |
| SLAM 地图已加载 | ❌ `~/maps/` 为空，需确认地图文件位置 |
| 有独立的人脸识别服务节点 | ✅ 人脸识别 HTTP 服务在 port 5001 运行正常 |

### 2.3 底盘控制 API（Rosmaster_Lib 可用方法）

Rosmaster_Lib 通过串口 (`/dev/myserial`, 115200 baud) 与 STM32 通信，提供以下关键 API：

```python
# ---- 运动控制 ----
set_car_run(state, speed)      # 方向控制: 1=前进,2=后退,3=左移,4=右移,5=左旋,6=右旋,7=停止
set_car_motion(v_x, v_y, v_z)  # 速度向量控制 (麦克纳姆轮)
set_motor(s1, s2, s3, s4)      # 四轮独立速度

# ---- 传感器反馈 ----
get_motor_encoder()             # 编码器数据 → 里程计
get_imu_attitude_data()         # IMU 姿态 (yaw/pitch/roll) → 航向
get_battery_voltage()           # 电池电压
get_version()                   # 固件版本

# ---- 其他 ----
set_beep(on_time)               # 蜂鸣器
set_pwm_servo(channel, angle)   # 舵机
```

### 2.4 TCP 协议 (App ↔ 小车, port 6000)

鸿蒙 App 与小车直接 TCP 通信，格式：

```
$ 01 TYP SIZE DATA CHECKSUM #
```

| 命令 | 功能 | App 端编码 | 小车端处理 |
|------|------|-----------|-----------|
| cmd 10 | 自由控制(x,y速度) | `CarEncode.CtrlCarEncode()` | → `set_car_motion()` |
| cmd 15 | 按钮控制(方向) | `CarEncode.ButtonCarEncode()` | → `set_car_run()` |
| cmd 21 | 四轮独立速度 | `CarEncode.UpSpeedCarEncode()` | → `set_motor()` |
| cmd 60-64 | 拍照/录像/循迹 | 对应编码函数 | 摄像头操作 |

### 2.5 关键约束

| 约束 | 说明 |
|------|------|
| ❌ STM32/AT32 固件 | **不可修改** |
| ✅ Rosmaster-App Python 层 | **可修改** (`~/Rosmaster-App/rosmaster/`) |
| ✅ Rosmaster_Lib | **可修改** (`py_install_V3.3.1/Rosmaster_Lib/`) |
| ✅ ROS2 节点 | **可新增** |
| ✅ 鸿蒙 App | **可修改** |
| ✅ 桌面 `tcp_ros_bridge.py` | **可修改** (但需部署到小车) |

---

## 三、方案选择

### 方案 A：安装 Nav2 完整导航栈

安装 Nav2 和相关依赖包，使用标准 ROS2 导航管道。

| 优点 | 缺点 |
|------|------|
| 成熟的导航框架 | 安装包多，Jetson arm64 兼容性风险 |
| 自带避障、路径规划 | `Rosmaster_Lib` 需封装成 ROS2 硬件驱动 |
| 适合后续扩展 | SLAM 需要额外配置 |

### 方案 B：基于 Rosmaster_Lib 的轻量导航 ⬅️ **推荐**

利用现有 Rosmaster_Lib API 实现简单航点导航：
- 编码器 → 里程计（Odometry）
- IMU → 航向（Yaw）
- 简单的 PID 控制器 → 逐点到点导航
- 复用激光雷达避障 (`laser_Avoidance_a1_X3.py`)

| 优点 | 缺点 |
|------|------|
| **不依赖 Nav2 安装** | 路径规划功能有限 |
| 直接用现有底盘 API | 建图需要额外方案 |
| 代码量可控，纯 Python | 不适合复杂环境 |
| 适合室内平地场景 | |

### 方案 C：混合模式

在 ROS2 中安装 `ros2-control` + `robot_localization`，发布标准 Odometry + TF，上层仍用 Nav2。

| 优点 | 缺点 |
|------|------|
| 渐进式架构 | 复杂度高于 B |
| 最终可升级到完整 Nav2 | 仍需要安装多个包 |

**推荐方案 B**——最务实，直接调用 Rosmaster_Lib API 实现导航，快速验证，后续可升级到 Nav2。

---

## 四、实施架构（方案 B）

```
鸿蒙 App
  │ TCP:6000 (现有, 不改)
  │ HTTP:7000 (新增)
  ▼
┌─────────────────────────────────────────────────────────┐
│  ros_http_api.py (新增 ROS2 节点, Flask, port 7000)      │
│                                                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │
│  │ WaypointNav   │  │ RescueNav    │  │ CoordTransform│   │
│  │ (航点引擎)     │  │ (救援状态机)  │  │ (坐标映射)    │   │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘   │
│         │                 │                  │           │
│  ┌──────▼─────────────────▼──────────────────▼───────┐   │
│  │  CarController (底盘控制适配器)                    │   │
│  │  封装 Rosmaster_Lib API                            │   │
│  │  - set_car_motion() → 速度控制                     │   │
│  │  - get_motor_encoder() → 里程计                    │   │
│  │  - get_imu_attitude_data() → 航向                  │   │
│  └──────────────────┬────────────────────────────────┘   │
└─────────────────────┼───────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────┐
│  Rosmaster_Lib (串口 → STM32 底盘)                      │
│  ├── set_car_motion(v_x, v_y, v_z)                      │
│  ├── get_motor_encoder()                                │
│  └── get_imu_attitude_data()                            │
│           │                                             │
└───────────┼─────────────────────────────────────────────┘
            │ USB/UART
            ▼
      STM32/AT32 底盘
```

注意：`ros_http_api.py` 运行在**小车**上，**不是**桌面上。它同时 import `Rosmaster_Lib` 和 `rclpy`。

---

## 五、新增模块详细设计

### 5.1 `ros_http_api.py` (在小车上运行)

```python
"""
ROS2 节点 + Flask HTTP 服务器，端口 7000
接收 App HTTP 请求，通过 Rosmaster_Lib 控制底盘，通过 rclpy 与 ROS2 交互

安装依赖:
  pip install flask
"""
import rclpy
from flask import Flask, request, jsonify
from Rosmaster_Lib import Rosmaster
import threading, json

# 初始化底盘
bot = Rosmaster(debug=False)
bot.create_receive_threading()

# 初始化 ROS2
rclpy.init()
node = rclpy.create_node('car_planning_node')

# HTTP API
app = Flask(__name__)

@app.route('/api/nav/waypoints', methods=['POST'])
def start_waypoint_nav():
    """接收航点列表，启动逐点导航"""
    data = request.get_json()
    waypoints = data.get('waypoints', [])
    # 启动导航线程
    threading.Thread(target=waypoint_nav_thread, args=(waypoints,), daemon=True).start()
    return jsonify({'status': 'navigating', 'count': len(waypoints)})

@app.route('/api/nav/stop', methods=['POST'])
def stop_nav():
    """停止导航"""
    global nav_running
    nav_running = False
    bot.set_car_motion(0, 0, 0)
    return jsonify({'status': 'stopped'})

@app.route('/api/nav/status', methods=['GET'])
def get_nav_status():
    """查询导航状态"""
    return jsonify(nav_status)

# ... 更多 API 端点 ...

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=7000)
```

### 5.2 `waypoint_navigator.py` (航点导航引擎)

核心导航逻辑：使用 Rosmaster_Lib 实现点到点导航。

```python
"""
轻量级航点导航器
方案：逐点导航，每个航点使用 PID 控制趋近
"""
import math, time
from Rosmaster_Lib import Rosmaster

class WaypointNavigator:
    def __init__(self, bot: Rosmaster):
        self.bot = bot
        self.waypoints = []        # [{x, y, theta}, ...]
        self.current_index = 0
        self.running = False
        self.status = 'idle'       # idle | navigating | paused | completed | failed
        
        # PID 参数
        self.kp_linear = 0.3       # 线速度比例
        self.kp_angular = 0.5      # 角速度比例
        self.waypoint_tolerance = 0.15  # 到达判定距离 (米)
        self.angle_tolerance = 0.1      # 到达判定角度 (弧度)
        self.max_speed = 50        # 最大速度 0-100
        
    def start(self, waypoints: list):
        """开始导航"""
        self.waypoints = waypoints
        self.current_index = 0
        self.running = True
        self.status = 'navigating'
        self._navigate_loop()
    
    def _navigate_loop(self):
        """导航主循环"""
        while self.running and self.current_index < len(self.waypoints):
            target = self.waypoints[self.current_index]
            self._navigate_to_pose(target['x'], target['y'], target.get('theta'))
            if self.running:
                self.current_index += 1
        if self.running:
            self.status = 'completed'
            self.bot.set_car_motion(0, 0, 0)
    
    def _navigate_to_pose(self, target_x, target_y, target_theta=None):
        """导航到单个目标点，使用闭环控制"""
        # 获取当前位置 (从编码器/IMU)
        # 1. 计算机器人到目标的距离和角度
        # 2. PID 输出速度
        # 3. 发送 set_car_motion()
        # 4. 循环直到到达容许误差内
        pass  # 具体实现在编码阶段完成
```

### 5.3 `coordinate_transform.py` (GPS ↔ 地图坐标)

```python
"""
GPS ↔ SLAM 地图坐标转换
方案: 单点 + 朝向校准
"""
import math

class CoordTransform:
    def __init__(self):
        self.ref_lat = None    # 参考点纬度
        self.ref_lng = None    # 参考点经度
        self.ref_x = 0.0       # 地图原点 X
        self.ref_y = 0.0       # 地图原点 Y
        self.heading = 0.0     # 地图朝向 (度, 正北=0)
        self.calibrated = False
    
    def set_reference(self, lat, lng, heading, map_x=0.0, map_y=0.0):
        """设置校准参考点"""
        self.ref_lat = lat
        self.ref_lng = lng
        self.heading = heading
        self.ref_x = map_x
        self.ref_y = map_y
        self.calibrated = True
    
    def gps_to_map(self, lat, lng):
        """GPS → 地图坐标"""
        if not self.calibrated:
            raise ValueError("未校准")
        dlat = lat - self.ref_lat
        dlng = lng - self.ref_lng
        dx_m = dlng * 111320.0 * math.cos(math.radians(self.ref_lat))
        dy_m = dlat * 111320.0
        h = math.radians(self.heading)
        map_x = self.ref_x + dx_m * math.cos(h) - dy_m * math.sin(h)
        map_y = self.ref_y + dx_m * math.sin(h) + dy_m * math.cos(h)
        return map_x, map_y
```

### 5.4 `rescue_nav.py` (救援状态机)

```python
"""
紧急救援状态机
流程: IDLE → SAVE_POS → TRANSFORM → NAV_TO → ARRIVED → NAV_BACK → COMPLETE
"""
from waypoint_navigator import WaypointNavigator
from coordinate_transform import CoordTransform

class RescueNav:
    def __init__(self, navigator: WaypointNavigator, transform: CoordTransform):
        self.nav = navigator
        self.transform = transform
        self.status = 'idle'    # idle | saving | transforming | going | arrived | returning | completed | aborted
        self.origin_pose = None  # 出发时的位姿
        self.target_map_pose = None  # 手机GPS转换后的地图坐标
    
    def start(self, phone_lat, phone_lng):
        """开始救援"""
        # 1. 保存当前位置
        self.origin_pose = self._get_current_pose()
        self.status = 'saving'
        
        # 2. GPS 转地图坐标
        self.target_map_pose = self.transform.gps_to_map(phone_lat, phone_lng)
        self.status = 'transforming'
        
        # 3. 导航到目标
        self.nav.start([self.target_map_pose])
        self.status = 'going'
        # ... 等待到达 ...
    
    def confirm_return(self):
        """确认上车，开始返航"""
        self.nav.start([self.origin_pose])
        self.status = 'returning'
    
    def abort(self):
        """中止"""
        self.nav.stop()
        self.status = 'aborted'
```

---

## 六、文件改动清单

### 6.1 新增文件（小车端，通过 SSH 部署）

| 文件 | 在小车上的路径 | 预估行数 | 说明 |
|------|--------------|---------|------|
| `ros_http_api.py` | `~/Rosmaster-App/rosmaster/ros_http_api.py` | 300 | Flask HTTP 服务器+导航API |
| `waypoint_navigator.py` | `~/Rosmaster-App/rosmaster/waypoint_navigator.py` | 250 | 航点导航引擎(PID闭环) |
| `coordinate_transform.py` | `~/Rosmaster-App/rosmaster/coordinate_transform.py` | 80 | GPS↔地图坐标转换 |
| `rescue_nav.py` | `~/Rosmaster-App/rosmaster/rescue_nav.py` | 200 | 救援状态机 |
| 启动脚本 | `~/Rosmaster-App/rosmaster/start_planning.sh` | 20 | 启动 HTTP 服务 |

### 6.2 新增文件（App 端）

| 文件 | 路径 | 预估行数 |
|------|------|---------|
| `HttpApi.ets` | `entry/src/main/ets/utils/HttpApi.ets` | 80 |
| `WaypointPage.ets` | `entry/src/main/ets/pages/WaypointPage.ets` | 300 |
| `RescuePage.ets` | `entry/src/main/ets/pages/RescuePage.ets` | 250 |

### 6.3 修改文件

| 文件 | 修改内容 |
|------|----------|
| `entry/src/main/ets/pages/Index.ets` | 添加"多点导航"+"紧急救援"入口按钮 |
| `entry/src/main/ets/pages/FaceRecognition.ets` | 检测到目标→弹窗确认→调用救援API |
| `entry/src/main/resources/base/profile/main_pages.json` | 注册新页面路由 |
| `~/Rosmaster-App/rosmaster/app.py` | 启动时也启动 ros_http_api.py (添加一行启动代码) |

### 6.4 不修改文件

| 文件 | 原因 |
|------|------|
| `tcp_ros_bridge.py` | 桌面文件，未部署到小车 |
| 鸿蒙 App TCP/编码层 | 协议不动 |
| STM32/AT32 固件 | 约束不可改 |
| Rosmaster_Lib | 直接 import 使用，不改源码 |

---

## 七、分阶段实施计划

### Phase 0: 环境准备 (1-2天)

**目标**：打通开发链路，确认小车可远程控制编程

```
Day 1 — 网络与访问
  ├── 确认小车 IP 稳定可 SSH
  ├── 测试 paramiko 远程执行（已可用 ✅）
  └── 确认文件读写权限

Day 2 — 开发环境验证
  ├── 测试: 通过 Python 远程执行 bot.set_car_run(1, 50) 让小车前进
  ├── 测试: 读取编码器数据 bot.get_motor_encoder()
  ├── 测试: 读取 IMU 数据 bot.get_imu_attitude_data()
  └── 确认 Flask 可用 (pip list 已有 ✅)
```

### Phase 1: 航点导航引擎 (4-5天)

**目标**：App 发送航点列表 → 小车依次到达 A→B→C

```
Day 1 — CarController 适配层
  ├── 实现: 里程计积分 (编码器→距离)
  ├── 实现: 航向追踪 (IMU yaw)
  └── 测试: 发送速度指令，读取反馈，打印定位

Day 2 — 点到点导航
  ├── 实现: 距离/角度计算 → PID 速度输出
  ├── 实现: 到达判定逻辑 (容忍半径)
  └── 测试: 从 A 点"走"到 B 点(坐标已知)

Day 3 — 逐点导航引擎
  ├── 实现: waypoint_navigator.py 完整逻辑
  ├── 多航点遍历、失败重试、停止
  └── 测试: A→B→C 三航点

Day 4 — ros_http_api.py HTTP 服务
  ├── Flask 服务器 + API 端点
  ├── 集成 waypoint_navigator
  └── 测试: curl 发送航点 → 导航

Day 5 — App 端对接
  ├── HttpApi.ets → 调用 HTTP API
  ├── WaypointPage.ets 页面开发
  ├── Index.ets 添加入口
  └── 端到端测试
```

### Phase 2: GPS 坐标映射 (1-2天)

```
Day 1 — 坐标映射服务
  ├── coordinate_transform.py 完成
  ├── ros_http_api.py 增加 /transform/* 端点
  └── 校准流程: 小车到原点, App记录GPS, 设朝向

Day 2 — 精度测试
  ├── 室外验证 GPS→地图偏差
  └── 如有需要增加两点校准
```

### Phase 3: 紧急救援 (3天)

```
Day 1 — 救援状态机
  ├── rescue_nav.py 状态机实现
  ├── ros_http_api.py 救援端点
  └── 单点测试: 模拟手机GPS→救援→到达

Day 2 — App 救援页面
  ├── RescuePage.ets 页面
  ├── 修改 FaceRecognition.ets 触发逻辑
  └── 救援状态实时显示

Day 3 — 全流程联调
  ├── 人脸识别→弹窗→救援→到达→确认→返航
  ├── 异常处理: 中止、超时、导航失败
  └── 安全机制验证
```

---

## 八、核心难点与对策

| 难点 | 对策 |
|------|------|
| **里程计累积误差** | 配合 IMU 航向修正；短距离导航误差小 |
| **GPS 室内信号差** | 使用室外校准 + 最后已知位置；室外使用 |
| **无 SLAM 地图** | 当前方案不需要地图，使用相对坐标；如需绝对坐标可安装 cartographer 建图 |
| **多线程安全** | HTTP 请求 + 导航循环 + ROS2 spinning 需用线程锁保护 |
| **电机 PID 调参** | 先固定参数，观察运动表现后微调 kp_linear / kp_angular |

---

## 九、验证标准

### Phase 1 验收

| 测试项 | 方法 | 预期 |
|--------|------|------|
| 导航到 1m 外点 | App 发航点 (1,0) | 小车前进约 1m 后停止 |
| 导航到 (1,1) | App 发航点 (1,1) | 小车走直角到目标 |
| 3 点连走 | A(0,0)→B(1,0)→C(0,1) | 依次到达，每点停 |
| 中途停止 | 发送 stop | 立即停止 |
| 状态查询 | GET /api/nav/status | 返回正确状态 |

### Phase 3 验收

| 测试项 | 预期 |
|--------|------|
| 模拟救援触发 | 小车前往指定 GPS 映射点 |
| 到达后确认返航 | 小车回到原点 |
| 中途中止 | 立即停止 |
| 无效 GPS 传入 | 返回错误提示 |

---

## 十、代码部署方式

所有小车端新增代码通过 paramiko SFTP 直接传输：

```python
# 部署脚本示例
import paramiko

client = paramiko.SSHClient()
client.connect('192.168.x.x', username='jetson', password='yahboom')
sftp = client.open_sftp()

# 上传文件
sftp.put('ros_http_api.py', '/home/jetson/Rosmaster-App/rosmaster/ros_http_api.py')
sftp.put('waypoint_navigator.py', '/home/jetson/Rosmaster-App/rosmaster/waypoint_navigator.py')

# 启动服务
stdin, stdout, stderr = client.exec_command(
    'source /opt/ros/foxy/setup.bash && '
    'cd ~/Rosmaster-App/rosmaster && '
    'python3 ros_http_api.py &'
)
```

---

## 十一、后续可升级方向

- **Nav2 集成**：当需要更复杂的路径规划时，安装 Nav2，将 CarController 封装为 ROS2 硬件驱动
- **SLAM 建图**：安装 cartographer 或 slam_toolbox，提供全局地图
- **语音控制**：接入语音识别，语音触发救援
- **多车协同**：多个小车共享地图，协同救援
