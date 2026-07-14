#!/bin/bash
# iCar 一键启动脚本
echo "=== iCar 启动 ==="

# 1. app.py (硬件控制: 马达/蜂鸣器, port 6000)
echo "[1/3] app.py (硬件控制 6000)..."
if ! fuser 6000/tcp 2>/dev/null; then
    pkill -f "app.py" 2>/dev/null || true
    sleep 1
    cd /home/jetson/Rosmaster-App/rosmaster
    nohup python3 app.py > /tmp/video.log 2>&1 &
    sleep 3
    echo "  app.py 已启动"
else
    echo "  app.py 已在运行"
fi

# 2. car_main.py (视频/AI/摔倒/音频/邮件, port 5000) — 使用正确路径
echo "[2/3] car_main.py (AI+视频 5000)..."
if ! fuser 5000/tcp 2>/dev/null; then
    cd /home/jetson/zihan-car/zihan_car_integration
    nohup python3 car_main.py > /tmp/car_main.log 2>&1 &
    echo "  启动中(模型预热约30秒)..."
else
    echo "  car_main.py 已在运行"
fi

# 3. bridge (智能对话转发, port 6001)
echo "[3/3] bridge (对话 6001)..."
sudo systemctl is-active --quiet tcp-ros-bridge || sudo systemctl restart tcp-ros-bridge
echo "  bridge 已就绪"

echo ""
echo "等待 car_main 模型预热..."
for i in $(seq 1 30); do
    if fuser 5000/tcp 2>/dev/null; then
        echo ""
        echo "=== 全部就绪 ==="
        netstat -tlnp 2>/dev/null | grep -E "5000|6000|6001"
        exit 0
    fi
    sleep 2
done

echo ""
echo "=== 端口状态 ==="
netstat -tlnp 2>/dev/null | grep -E "5000|6000|6001"
echo "注意: port 5000 未就绪，请检查 /tmp/car_main.log"
