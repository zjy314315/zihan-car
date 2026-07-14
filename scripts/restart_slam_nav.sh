#!/bin/bash
# Kill old, restart slam_nav_service, verify

echo "=== Killing old slam_nav_service ==="
pkill -f slam_nav_service 2>/dev/null
sleep 2
ps aux | grep slam_nav | grep -v grep || echo "(none)"

echo ""
echo "=== Port 7000 ==="
ss -tlnp 2>/dev/null | grep 7000 || echo "port 7000 free"

echo ""
echo "=== Verify patch ==="
grep -n 'silent=True' /home/jetson/Rosmaster-App/rosmaster/slam_nav_service.py

echo ""
echo "=== Starting slam_nav_service ==="
source /opt/ros/foxy/setup.bash
source /home/jetson/code/software/library_ws/install/setup.bash
cd /home/jetson/Rosmaster-App/rosmaster
python3 slam_nav_service.py > /tmp/slam_logs/slam_nav.log 2>&1 &
SLAM_PID=$!
echo "PID: $SLAM_PID"
sleep 5

echo ""
echo "=== OPTIONS preflight ==="
curl -s -D- -X OPTIONS http://localhost:7000/api/map/build/end \
  -H 'Origin: null' \
  -H 'Access-Control-Request-Method: POST' \
  -H 'Access-Control-Request-Headers: content-type' 2>&1 | head -25

echo ""
echo "=== API test ==="
curl -s http://localhost:7000/api/system/ping
echo ""
curl -s http://localhost:7000/api/system/pose
echo ""

echo ""
echo "=== build/end test ==="
curl -s -X POST http://localhost:7000/api/map/build/end \
  -H 'Content-Type: application/json' \
  -d '{}'
echo ""
