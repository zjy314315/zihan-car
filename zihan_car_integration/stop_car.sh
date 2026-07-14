#!/bin/bash
# iCar 一键停止脚本
echo "=== 停止所有服务 ==="

pkill -f "car_main.py" 2>/dev/null && echo "[OK] car_main.py 已停止" || echo "[--] car_main.py 未运行"
pkill -f "Rosmaster-App/rosmaster/app.py" 2>/dev/null && echo "[OK] app.py 已停止" || echo "[--] app.py 未运行"
pkill -f "car_intelligent_monitor.py" 2>/dev/null && echo "[OK] monitor 已停止" || echo "[--] monitor 未运行"
sudo systemctl stop tcp-ros-bridge 2>/dev/null && echo "[OK] bridge 已停止" || echo "[--] bridge 未运行"

sleep 1
fuser -k 5000/tcp 2>/dev/null || true
fuser -k 6000/tcp 2>/dev/null || true
fuser -k 6001/tcp 2>/dev/null || true

echo ""
echo "所有服务已停止"
