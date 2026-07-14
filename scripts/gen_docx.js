const fs = require("fs");
const {
  Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell,
  Header, Footer, AlignmentType, LevelFormat,
  HeadingLevel, BorderStyle, WidthType, ShadingType,
  PageNumber, PageBreak, ExternalHyperlink, TableOfContents
} = require("docx");

const border = { style: BorderStyle.SINGLE, size: 1, color: "CCCCCC" };
const borders = { top: border, bottom: border, left: border, right: border };
const cellMargins = { top: 60, bottom: 60, left: 100, right: 100 };

function headerCell(text, width) {
  return new TableCell({
    borders,
    width: { size: width, type: WidthType.DXA },
    shading: { fill: "2B579A", type: ShadingType.CLEAR },
    margins: cellMargins,
    verticalAlign: "center",
    children: [new Paragraph({ alignment: AlignmentType.CENTER, children: [new TextRun({ text, bold: true, color: "FFFFFF", font: "Arial", size: 20 })] })],
  });
}

function cell(text, width, opts = {}) {
  return new TableCell({
    borders,
    width: { size: width, type: WidthType.DXA },
    shading: opts.shading ? { fill: opts.shading, type: ShadingType.CLEAR } : undefined,
    margins: cellMargins,
    children: [new Paragraph({ children: [new TextRun({ text, font: "Arial", size: 20, ...opts })] })],
  });
}

function h1(text) {
  return new Paragraph({ heading: HeadingLevel.HEADING_1, spacing: { before: 360, after: 200 }, children: [new TextRun({ text, bold: true, font: "Arial", size: 32, color: "2B579A" })] });
}

function h2(text) {
  return new Paragraph({ heading: HeadingLevel.HEADING_2, spacing: { before: 280, after: 160 }, children: [new TextRun({ text, bold: true, font: "Arial", size: 26, color: "2B579A" })] });
}

function h3(text) {
  return new Paragraph({ heading: HeadingLevel.HEADING_3, spacing: { before: 200, after: 120 }, children: [new TextRun({ text, bold: true, font: "Arial", size: 22, color: "333333" })] });
}

function p(text, opts = {}) {
  return new Paragraph({ spacing: { after: 120 }, children: [new TextRun({ text, font: "Arial", size: 21, ...opts })] });
}

function boldBullet(text) {
  return new Paragraph({
    numbering: { reference: "bullets", level: 0 },
    spacing: { after: 60 },
    children: [new TextRun({ text, font: "Arial", size: 21 })],
  });
}

function codeBlock(text) {
  return new Paragraph({
    spacing: { before: 80, after: 80 },
    indent: { left: 360 },
    shading: { type: ShadingType.CLEAR, fill: "F5F5F5" },
    children: [new TextRun({ text, font: "Courier New", size: 18, color: "333333" })],
  });
}

function spacer() {
  return new Paragraph({ spacing: { after: 60 }, children: [] });
}

// ======================== TABLE WIDTHS ========================
const FW = 9360; // full width US letter with 1" margins

// ======================== BUILD ========================
const doc = new Document({
  styles: {
    default: { document: { run: { font: "Arial", size: 21 } } },
    paragraphStyles: [
      { id: "Heading1", name: "Heading 1", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { size: 32, bold: true, font: "Arial", color: "2B579A" },
        paragraph: { spacing: { before: 360, after: 200 }, outlineLevel: 0 } },
      { id: "Heading2", name: "Heading 2", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { size: 26, bold: true, font: "Arial", color: "2B579A" },
        paragraph: { spacing: { before: 280, after: 160 }, outlineLevel: 1 } },
      { id: "Heading3", name: "Heading 3", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { size: 22, bold: true, font: "Arial", color: "333333" },
        paragraph: { spacing: { before: 200, after: 120 }, outlineLevel: 2 } },
    ]
  },
  numbering: {
    config: [{
      reference: "bullets",
      levels: [{ level: 0, format: LevelFormat.BULLET, text: "•", alignment: AlignmentType.LEFT,
        style: { paragraph: { indent: { left: 720, hanging: 360 } } } }],
    }, {
      reference: "numbers",
      levels: [{ level: 0, format: LevelFormat.DECIMAL, text: "%1.", alignment: AlignmentType.LEFT,
        style: { paragraph: { indent: { left: 720, hanging: 360 } } } }],
    }],
  },
  sections: [{
    properties: {
      page: {
        size: { width: 12240, height: 15840 },
        margin: { top: 1440, right: 1440, bottom: 1440, left: 1440 },
      }
    },
    headers: {
      default: new Header({
        children: [new Paragraph({
          alignment: AlignmentType.RIGHT,
          border: { bottom: { style: BorderStyle.SINGLE, size: 4, color: "2B579A", space: 4 } },
          children: [new TextRun({ text: "智能小车 SLAM 导航系统", font: "Arial", size: 18, color: "888888" })],
        })]
      }),
    },
    footers: {
      default: new Footer({
        children: [new Paragraph({
          alignment: AlignmentType.CENTER,
          border: { top: { style: BorderStyle.SINGLE, size: 2, color: "CCCCCC", space: 4 } },
          children: [
            new TextRun({ text: "第 ", font: "Arial", size: 18, color: "888888" }),
            new TextRun({ children: [PageNumber.CURRENT], font: "Arial", size: 18, color: "888888" }),
            new TextRun({ text: " 页", font: "Arial", size: 18, color: "888888" }),
          ],
        })]
      }),
    },
    children: [
      // ====== COVER PAGE ======
      new Paragraph({ spacing: { before: 3000 }, children: [] }),
      new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 200 },
        children: [new TextRun({ text: "智能小车 SLAM 导航系统", font: "Arial", size: 52, bold: true, color: "2B579A" })] }),
      new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 100 },
        children: [new TextRun({ text: "基于 ROS2 Foxy + RPLIDAR + Gmapping", font: "Arial", size: 28, color: "666666" })] }),
      new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 60 },
        children: [new TextRun({ text: "鸿蒙 App 遥控 + 自动导航", font: "Arial", size: 28, color: "666666" })] }),
      new Paragraph({ alignment: AlignmentType.CENTER, spacing: { before: 600, after: 60 },
        children: [new TextRun({ text: "版本: 2.0", font: "Arial", size: 22, color: "888888" })] }),
      new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 60 },
        children: [new TextRun({ text: "日期: 2026年7月", font: "Arial", size: 22, color: "888888" })] }),
      new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 60 },
        children: [new TextRun({ text: "硬件: Jetson Orin NX (aarch64)", font: "Arial", size: 22, color: "888888" })] }),
      new Paragraph({ children: [new PageBreak()] }),

      // ====== TOC ======
      h1("目录"),
      new TableOfContents("Table of Contents", { hyperlink: true, headingStyleRange: "1-3" }),
      new Paragraph({ children: [new PageBreak()] }),

      // ====== 1. PROJECT OVERVIEW ======
      h1("1. 项目概述"),
      p("本项目实现了一个基于 ROS2 Foxy 的智能小车 SLAM 导航系统，支持鸿蒙 HarmonyOS App 遥控、Windows 浏览器遥控、地图构建、语音对话和最短路径自动导航等功能。"),

      h2("1.1 系统架构"),
      p("系统采用模块化设计，主要分为以下层："),
      boldBullet("硬件层: Jetson Orin NX + RPLIDAR A1/A2 激光雷达 + 麦克纳姆轮底盘 + USB音箱 + 讯飞麦克风"),
      boldBullet("ROS2 中间层: RPLIDAR 驱动 + Gmapping SLAM 建图 + TF 坐标树"),
      boldBullet("应用层: slam_nav_service (HTTP API 端口7000) + 语音对话 + TCP 桥接"),
      boldBullet("交互层: 鸿蒙 App (HarmonyOS ArkTS) + Windows Web 控制页面 (car_control.html)"),

      h2("1.2 核心功能"),
      new Table({ width: { size: FW, type: WidthType.DXA }, columnWidths: [3120, 6240], rows: [
        new TableRow({ children: [headerCell("功能模块", 3120), headerCell("说明", 6240)] }),
        new TableRow({ children: [cell("SLAM 实时建图", 3120, { bold: true }), cell("RPLIDAR 10Hz 扫描 + Gmapping 在线构建二维地图", 6240)] }),
        new TableRow({ children: [cell("地图航点记录", 3120, { bold: true, shading: "F2F7FB" }), cell("用户遥控小车到目标位置，一键记录当前坐标为航点", 6240, { shading: "F2F7FB" })] }),
        new TableRow({ children: [cell("TSP 最短路径导航", 3120, { bold: true }), cell("从当前位置出发，计算访问所有航点的最短路径，自动循航", 6240)] }),
        new TableRow({ children: [cell("语音对话", 3120, { bold: true, shading: "F2F7FB" }), cell("离线中文语音识别 + Ollama 大模型对话 + USB音箱播报", 6240, { shading: "F2F7FB" })] }),
        new TableRow({ children: [cell("多端遥控", 3120, { bold: true }), cell("鸿蒙 App、Windows 浏览器、WASD 键盘多种控制方式", 6240)] }),
      ]}),
      spacer(),
      new Paragraph({ children: [new PageBreak()] }),

      // ====== 2. HARDWARE ======
      h1("2. 硬件配置"),
      h2("2.1 硬件清单"),
      new Table({ width: { size: FW, type: WidthType.DXA }, columnWidths: [2500, 3000, 3860], rows: [
        new TableRow({ children: [headerCell("设备", 2500), headerCell("型号", 3000), headerCell("备注", 3860)] }),
        new TableRow({ children: [cell("主控均片", 2500, { bold: true }), cell("Jetson Orin NX", 3000), cell("aarch64, Ubuntu 20.04", 3860)] }),
        new TableRow({ children: [cell("激光雷达", 2500, { bold: true, shading: "F2F7FB" }), cell("RPLIDAR A1/A2", 3000, { shading: "F2F7FB" }), cell("10Hz, 12m, 115200 baud, /dev/rplidar", 3860, { shading: "F2F7FB" })] }),
        new TableRow({ children: [cell("底盘", 2500, { bold: true }), cell("Rosmaster 麦克纳姆轮底盘", 3000), cell("串口 /dev/myserial, Rosmaster_Lib", 3860)] }),
        new TableRow({ children: [cell("音箱", 2500, { bold: true, shading: "F2F7FB" }), cell("C-Media USB 音箱", 3000, { shading: "F2F7FB" }), cell("ALSA card 0, device 0", 3860, { shading: "F2F7FB" })] }),
        new TableRow({ children: [cell("麦克风", 2500, { bold: true }), cell("讯飞麦克风", 3000), cell("ALSA card 2", 3860)] }),
        new TableRow({ children: [cell("深度传感器", 2500, { bold: true, shading: "F2F7FB" }), cell("ORBBEC深度传感器", 3000, { shading: "F2F7FB" }), cell("ALSA card 1", 3860, { shading: "F2F7FB" })] }),
      ]}),

      h2("2.2 网络配置"),
      new Table({ width: { size: FW, type: WidthType.DXA }, columnWidths: [2500, 6860], rows: [
        new TableRow({ children: [headerCell("项目", 2500), headerCell("值", 6860)] }),
        new TableRow({ children: [cell("IP地址", 2500, { bold: true }), cell("10.168.202.242 (SSH: jetson / yahboom)", 6860)] }),
        new TableRow({ children: [cell("串口", 2500, { bold: true, shading: "F2F7FB" }), cell("RPLIDAR: /dev/rplidar (ttyUSB0, 115200) | 底盘: /dev/myserial (ttyUSB1, 115200)", 6860, { shading: "F2F7FB" })] }),
        new TableRow({ children: [cell("ROS2", 2500, { bold: true }), cell("Foxy, library_ws, slam_gmapping + sllidar_ros2", 6860)] }),
      ]}),
      spacer(),
      new Paragraph({ children: [new PageBreak()] }),

      // ====== 3. SOFTWARE ARCHITECTURE ======
      h1("3. 软件架构"),
      h2("3.1 服务端口分配"),
      new Table({ width: { size: FW, type: WidthType.DXA }, columnWidths: [1500, 3000, 4860], rows: [
        new TableRow({ children: [headerCell("端口", 1500), headerCell("服务", 3000), headerCell("说明", 4860)] }),
        new TableRow({ children: [cell("22", 1500), cell("SSH", 3000), cell("远程登录", 4860)] }),
        new TableRow({ children: [cell("4000", 1500, { shading: "F2F7FB" }), cell("原厂 Web 服务", 3000, { shading: "F2F7FB" }), cell("原厂 app.py 的 Web 接口", 4860, { shading: "F2F7FB" })] }),
        new TableRow({ children: [cell("6001", 1500), cell("TCP-ROS Bridge", 3000), cell("HarmonyOS App TCP 桥接", 4860)] }),
        new TableRow({ children: [cell("7000", 1500, { bold: true, shading: "F2F7FB" }), cell("slam_nav_service", 3000, { bold: true, shading: "F2F7FB" }), cell("SLAM 建图 + 导航 HTTP API (Flask)", 4860, { shading: "F2F7FB" })] }),
        new TableRow({ children: [cell("11434", 1500), cell("Ollama", 3000), cell("LLM 对话服务", 4860)] }),
      ]}),

      h2("3.2 ROS2 TF 坐标树"),
      p("系统采用以下 TF 坐标树链："),
      codeBlock("map → odom → base_link → laser"),
      boldBullet("map → odom: Gmapping 发布，表示地图坐标系下的位姿"),
      boldBullet("odom → base_link: slam_nav_service 发布，基于编码器统计走行距离 (20Hz)"),
      boldBullet("base_link → laser: slam_nav_service 发布，固定关节 (z=0.05m)"),

      h2("3.3 文件结构"),
      new Table({ width: { size: FW, type: WidthType.DXA }, columnWidths: [3500, 5860], rows: [
        new TableRow({ children: [headerCell("文件", 3500), headerCell("说明", 5860)] }),
        new TableRow({ children: [cell("car_planning/slam_nav_service.py", 3500, { bold: true }), cell("主服务程序：SLAM建图 + TSP导航 + HTTP API", 5860)] }),
        new TableRow({ children: [cell("car_planning/position_recorder.py", 3500, { bold: true, shading: "F2F7FB" }), cell("航点记录器（方案C）", 5860, { shading: "F2F7FB" })] }),
        new TableRow({ children: [cell("car_planning/car_controller.py", 3500, { bold: true }), cell("底盘控制封装（Rosmaster_Lib）", 5860)] }),
        new TableRow({ children: [cell("car_planning/keyboard_control.py", 3500, { bold: true, shading: "F2F7FB" }), cell("WASD 键盘遥控（termios）", 5860, { shading: "F2F7FB" })] }),
        new TableRow({ children: [cell("car_planning/waypoint_navigator.py", 3500, { bold: true }), cell("航点导航引擎", 5860)] }),
        new TableRow({ children: [cell("tcp_ros_bridge.py", 3500, { bold: true, shading: "F2F7FB" }), cell("TCP→ROS 桥接", 5860, { shading: "F2F7FB" })] }),
        new TableRow({ children: [cell("car_control.html", 3500, { bold: true }), cell("Windows 浏览器控制页面", 5860)] }),
        new TableRow({ children: [cell("voice_assistant/", 3500, { bold: true, shading: "F2F7FB" }), cell("语音对话模块（ASR + LLM + TTS）", 5860, { shading: "F2F7FB" })] }),
        new TableRow({ children: [cell("zihan_car_integration/", 3500, { bold: true }), cell("智能监控模块（人脸识别、摔倒检测等）", 5860)] }),
      ]}),
      spacer(),
      new Paragraph({ children: [new PageBreak()] }),

      // ====== 4. API REFERENCE ======
      h1("4. API 参考"),
      p("slam_nav_service 在端口 7000 提供 HTTP REST API，支持 CORS（允许浏览器跨域请求）。"),

      h2("4.1 系统 API"),
      new Table({ width: { size: FW, type: WidthType.DXA }, columnWidths: [2500, 1200, 1200, 4460], rows: [
        new TableRow({ children: [headerCell("路径", 2500), headerCell("方法", 1200), headerCell("参数", 1200), headerCell("返回", 4460)] }),
        new TableRow({ children: [cell("/api/system/ping", 2500, { bold: true }), cell("GET", 1200), cell("-", 1200), cell("心跳检查: {status: ok, message: pong}", 4460)] }),
        new TableRow({ children: [cell("/api/system/pose", 2500, { bold: true, shading: "F2F7FB" }), cell("GET", 1200, { shading: "F2F7FB" }), cell("-", 1200, { shading: "F2F7FB" }), cell("当前SLAM位置: {x, y, yaw, frame}", 4460, { shading: "F2F7FB" })] }),
      ]}),

      h2("4.2 地图构建 API"),
      new Table({ width: { size: FW, type: WidthType.DXA }, columnWidths: [2500, 1200, 1200, 4460], rows: [
        new TableRow({ children: [headerCell("路径", 2500), headerCell("方法", 1200), headerCell("参数", 1200), headerCell("说明", 4460)] }),
        new TableRow({ children: [cell("/api/map/build/start", 2500, { bold: true }), cell("POST", 1200), cell("-", 1200), cell("开始构建，记录当前位置为原点", 4460)] }),
        new TableRow({ children: [cell("/api/map/control", 2500, { bold: true, shading: "F2F7FB" }), cell("POST", 1200, { shading: "F2F7FB" }), cell("{vx, vy, vz}", 1200, { shading: "F2F7FB" }), cell("速度控制（用于遥控）", 4460, { shading: "F2F7FB" })] }),
        new TableRow({ children: [cell("/api/map/waypoint", 2500, { bold: true }), cell("POST", 1200), cell("{name}", 1200), cell("记录当前位置为航点", 4460)] }),
        new TableRow({ children: [cell("/api/map/build/end", 2500, { bold: true, shading: "F2F7FB" }), cell("POST", 1200, { shading: "F2F7FB" }), cell("{name, force}", 1200, { shading: "F2F7FB" }), cell("结束构建，保存地图。force=true可覆盖重名", 4460, { shading: "F2F7FB" })] }),
        new TableRow({ children: [cell("/api/map/info", 2500, { bold: true }), cell("GET", 1200), cell("-", 1200), cell("当前构建中的地图状态", 4460)] }),
        new TableRow({ children: [cell("/api/map/list", 2500, { bold: true, shading: "F2F7FB" }), cell("GET", 1200, { shading: "F2F7FB" }), cell("-", 1200, { shading: "F2F7FB" }), cell("列出所有已保存的地图", 4460, { shading: "F2F7FB" })] }),
        new TableRow({ children: [cell("/api/map/move_dir", 2500, { bold: true }), cell("POST", 1200), cell("{direction, distance}", 1200), cell("方向移动（forward/backward/left/right）", 4460)] }),
      ]}),

      h2("4.3 导航 API"),
      new Table({ width: { size: FW, type: WidthType.DXA }, columnWidths: [2500, 1200, 1200, 4460], rows: [
        new TableRow({ children: [headerCell("路径", 2500), headerCell("方法", 1200), headerCell("参数", 1200), headerCell("说明", 4460)] }),
        new TableRow({ children: [cell("/api/map/navigate", 2500, { bold: true }), cell("POST", 1200), cell("{name}", 1200), cell("按 TSP 最短路径循航地图所有航点", 4460)] }),
        new TableRow({ children: [cell("/api/map/stop", 2500, { bold: true, shading: "F2F7FB" }), cell("POST", 1200, { shading: "F2F7FB" }), cell("-", 1200, { shading: "F2F7FB" }), cell("停止导航", 4460, { shading: "F2F7FB" })] }),
        new TableRow({ children: [cell("/api/map/status", 2500, { bold: true }), cell("GET", 1200), cell("-", 1200), cell("导航状态 + 当前位置", 4460)] }),
        new TableRow({ children: [cell("/api/map/move_to", 2500, { bold: true, shading: "F2F7FB" }), cell("POST", 1200, { shading: "F2F7FB" }), cell("{x, y}", 1200, { shading: "F2F7FB" }), cell("导航到指定坐标", 4460, { shading: "F2F7FB" })] }),
        new TableRow({ children: [cell("/api/nav/obstacle", 2500, { bold: true }), cell("GET", 1200), cell("-", 1200), cell("前方障碍物距离", 4460)] }),
      ]}),
      spacer(),
      new Paragraph({ children: [new PageBreak()] }),

      // ====== 5. DEPLOYMENT ======
      h1("5. 部署指南"),
      h2("5.1 快速启动"),
      p("1. SSH 连接小车："),
      codeBlock("ssh jetson@10.168.202.242  # 密码: yahboom"),
      p("2. 启动 SLAM 全栈："),
      codeBlock("cd ~/Rosmaster-App/rosmaster && bash start_slam_stack.sh"),
      p("3. 打开 Windows 控制页面："),
      codeBlock("双击打开 car_control.html"),

      h2("5.2 服务列表"),
      new Table({ width: { size: FW, type: WidthType.DXA }, columnWidths: [2200, 1500, 5660], rows: [
        new TableRow({ children: [headerCell("服务", 2200), headerCell("启动方式", 1500), headerCell("说明", 5660)] }),
        new TableRow({ children: [cell("RPLIDAR", 2200, { bold: true }), cell("start_slam_stack.sh", 1500), cell("ros2 launch sllidar_ros2 sllidar_launch.py serial_port:=/dev/rplidar serial_baudrate:=115200", 5660)] }),
        new TableRow({ children: [cell("Gmapping", 2200, { bold: true, shading: "F2F7FB" }), cell("start_slam_stack.sh", 1500, { shading: "F2F7FB" }), cell("ros2 launch slam_gmapping slam_gmapping.launch.py", 5660, { shading: "F2F7FB" })] }),
        new TableRow({ children: [cell("slam_nav_service", 2200, { bold: true }), cell("start_slam_stack.sh", 1500), cell("python3 slam_nav_service.py (HTTP API port 7000)", 5660)] }),
        new TableRow({ children: [cell("TCP-ROS Bridge", 2200, { bold: true, shading: "F2F7FB" }), cell("systemd", 1500, { shading: "F2F7FB" }), cell("tcp-ros-bridge.service (port 6001)", 5660, { shading: "F2F7FB" })] }),
        new TableRow({ children: [cell("语音对话", 2200, { bold: true }), cell("systemd", 1500), cell("voice-assistant.service", 5660)] }),
      ]}),

      h2("5.3 日志查看"),
      new Table({ width: { size: FW, type: WidthType.DXA }, columnWidths: [2500, 6860], rows: [
        new TableRow({ children: [headerCell("日志文件", 2500), headerCell("命令", 6860)] }),
        new TableRow({ children: [cell("RPLIDAR", 2500, { bold: true }), cell("tail -f /tmp/slam_logs/rplidar.log", 6860)] }),
        new TableRow({ children: [cell("Gmapping", 2500, { bold: true, shading: "F2F7FB" }), cell("tail -f /tmp/slam_logs/gmapping.log", 6860, { shading: "F2F7FB" })] }),
        new TableRow({ children: [cell("slam_nav_service", 2500, { bold: true }), cell("tail -f /tmp/slam_logs/slam_nav.log", 6860)] }),
      ]}),
      spacer(),
      new Paragraph({ children: [new PageBreak()] }),

      // ====== 6. USAGE ======
      h1("6. 使用指南"),
      h2("6.1 方案对比"),
      p("经过多轮测试，目前推荐以下三种方案："),
      new Table({ width: { size: FW, type: WidthType.DXA }, columnWidths: [1200, 2700, 2700, 2760], rows: [
        new TableRow({ children: [headerCell("", 1200), headerCell("方案A 自动move_dir", 2700), headerCell("方案B 键盘WASD", 2700), headerCell("方案C App遥控 ★", 2760)] }),
        new TableRow({ children: [cell("控制", 1200, { bold: true }), cell("脱机自动", 2700), cell("SSH终端WASD", 2700), cell("原厂App/浏览器", 2760)] }),
        new TableRow({ children: [cell("优点", 1200, { bold: true, shading: "F2F7FB" }), cell("全自动无需人", 2700, { shading: "F2F7FB" }), cell("随时可停", 2700, { shading: "F2F7FB" }), cell("不碰串口，不冲突", 2760, { shading: "F2F7FB" })] }),
        new TableRow({ children: [cell("缺点", 1200, { bold: true }), cell("编码器系数不准，SLAM位置更新慢", 2700), cell("termios不灵敏，需NoMachine终端", 2700), cell("需要人手动遥控", 2760)] }),
      ]}),
      p("推荐: 方案C » 方案B » 方案A"),

      h2("6.2 方案C 完整流程"),
      p("★ 推荐方案：浏览器遥控 + position_recorder 只读位置"),
      p("步骤1：启动服务"),
      codeBlock("cd ~/Rosmaster-App/rosmaster && bash start_slam_stack.sh"),
      p("步骤2：打开 car_control.html，确认连接成功"),
      p("步骤3：点击「开始构建」记录原点"),
      p("步骤4：用方向键/WASD/鼠标拖动把车开到目标位置"),
      p("步骤5：输入名称→点「记录航点」"),
      p("步骤6：重复步骤4-5直到所有航点记录完毕"),
      p("步骤7：点「保存结束」，地图自动存入小车 maps/目录"),

      h2("6.3 自动导航"),
      p("保存地图后，可通过API启动自动导航："),
      codeBlock("# 启动导航（小车自动访问所有航点）"),
      codeBlock("curl -X POST http://10.168.202.242:7000/api/map/navigate \\"),
      codeBlock("  -H \"Content-Type: application/json\" -d '{\"name\":\"你的路线名称\"}'"),
      spacer(),
      codeBlock("# 查看导航状态"),
      codeBlock("curl http://10.168.202.242:7000/api/map/status"),
      spacer(),
      codeBlock("# 停止导航"),
      codeBlock("curl -X POST http://10.168.202.242:7000/api/map/stop"),
      p("注意：导航仅访问航点（跳过原点），会根据当前位置自动计算 TSP 最短路径。"),
      spacer(),
      new Paragraph({ children: [new PageBreak()] }),

      // ====== 7. KNOWN ISSUES ======
      h1("7. 已知问题"),
      h2("7.1 P0 - 串口冲突"),
      p("原因: app.py（原厂程序）会自动启动，与 slam_nav_service 争夺 /dev/myserial"),
      p("解决: 使用方案C，position_recorder.py 不碰串口，配合 app.py 使用"),
      p("启动脚本: ~/Rosmaster-App/rosmaster/start_app.sh"),

      h2("7.2 P1 - 编码器系数不准"),
      p("car_controller.py 中 encoder_to_meter = 0.001 偏大，实际系数约 0.0001（差10倍）。影响方案A的自动移动控制。"),

      h2("7.3 P2 - SLAM 位置跳变"),
      p("在开环境下 Gmapping 扫描匹配不稳定，配合麦轮打滑导致位置突然跳变。"),
      p("正在解决: 将 navigate_to 改为混合定位模式（IMU转向 + 编码器走直线 + SLAM终点校验）。"),

      h2("7.4 P3 - 重启后坐标系变更"),
      p("每次重启 Gmapping，地图坐标系从零开始，旧航点坐标失效。待实现地图持久化保存/加载功能。"),
      spacer(),
      new Paragraph({ children: [new PageBreak()] }),

      // ====== 8. APPENDIX ======
      h1("8. 附录"),
      h2("8.1 常用命令"),
      new Table({ width: { size: FW, type: WidthType.DXA }, columnWidths: [4000, 5360], rows: [
        new TableRow({ children: [headerCell("命令", 4000), headerCell("说明", 5360)] }),
        new TableRow({ children: [cell("ssh jetson@10.168.202.242", 4000), cell("SSH连接小车", 5360)] }),
        new TableRow({ children: [cell("bash start_slam_stack.sh", 4000, { shading: "F2F7FB" }), cell("启动全部SLAM服务", 5360, { shading: "F2F7FB" })] }),
        new TableRow({ children: [cell("tail -f /tmp/slam_logs/slam_nav.log", 4000), cell("查看服务日志", 5360)] }),
        new TableRow({ children: [cell("curl http://localhost:7000/api/system/ping", 4000, { shading: "F2F7FB" }), cell("测试API是否在线", 5360, { shading: "F2F7FB" })] }),
        new TableRow({ children: [cell("aplay -D plughw:0,0 ~/file.wav", 4000), cell("USB音箱播放音频", 5360)] }),
        new TableRow({ children: [cell("pkill -f slam_nav_service", 4000, { shading: "F2F7FB" }), cell("停止服务", 5360, { shading: "F2F7FB" })] }),
      ]}),

      h2("8.2 重要路径"),
      new Table({ width: { size: FW, type: WidthType.DXA }, columnWidths: [3000, 6360], rows: [
        new TableRow({ children: [headerCell("路径", 3000), headerCell("说明", 6360)] }),
        new TableRow({ children: [cell("~/Rosmaster-App/rosmaster/", 3000), cell("代码主目录", 6360)] }),
        new TableRow({ children: [cell("~/Rosmaster-App/rosmaster/maps/", 3000, { shading: "F2F7FB" }), cell("已保存地图文件 (.json)", 6360, { shading: "F2F7FB" })] }),
        new TableRow({ children: [cell("~/code/software/library_ws/", 3000), cell("SLAM工作空间 (sllidar_ros2, slam_gmapping)", 6360)] }),
        new TableRow({ children: [cell("/tmp/slam_logs/", 3000, { shading: "F2F7FB" }), cell("运行日志", 6360, { shading: "F2F7FB" })] }),
        new TableRow({ children: [cell("C:\\Users\\21774\\Desktop\\car_control.html", 3000), cell("Windows控制页面", 6360)] }),
      ]}),
      spacer(),
      p("— 文档结束 —", { alignment: AlignmentType.CENTER, color: "888888" }),
    ],
  }],
});

Packer.toBuffer(doc).then(buffer => {
  const outPath = "C:\\Users\\21774\\Desktop\\智能小车SLAM导航系统.docx";
  fs.writeFileSync(outPath, buffer);
  console.log("OK: saved to", outPath);
});
