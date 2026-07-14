#!/bin/bash
# Start full SLAM stack: RPLIDAR + gmapping + slam_nav_service
# Run on car: bash start_slam_stack.sh

source /opt/ros/foxy/setup.bash
source /home/jetson/code/software/library_ws/install/setup.bash

export RCLPY_LOG_LEVEL=INFO
LOGDIR=/tmp/slam_logs
mkdir -p $LOGDIR

echo "=== Starting SLAM Stack ==="

# 1. RPLIDAR
echo "[1/3] Starting RPLIDAR..."
ros2 launch sllidar_ros2 sllidar_launch.py \
  serial_port:=/dev/rplidar \
  serial_baudrate:=115200 \
  frame_id:=laser \
  > $LOGDIR/rplidar.log 2>&1 &
RPLIDAR_PID=$!
echo "  PID: $RPLIDAR_PID"
sleep 2

# 2. gmapping
echo "[2/3] Starting gmapping SLAM..."
ros2 launch slam_gmapping slam_gmapping.launch.py \
  > $LOGDIR/gmapping.log 2>&1 &
GMAPPING_PID=$!
echo "  PID: $GMAPPING_PID"
sleep 3

# 3. slam_nav_service (port 7000)
echo "[3/3] Starting slam_nav_service (port 7000)..."
cd /home/jetson/Rosmaster-App/rosmaster
python3 slam_nav_service.py \
  > $LOGDIR/slam_nav.log 2>&1 &
SLAM_NAV_PID=$!
echo "  PID: $SLAM_NAV_PID"

echo ""
echo "=== All services started ==="
echo "Logs: $LOGDIR/"
echo "  RPLIDAR:  $LOGDIR/rplidar.log"
echo "  gmapping: $LOGDIR/gmapping.log"
echo "  Nav API:  $LOGDIR/slam_nav.log"
echo ""
echo "To check: tail -f $LOGDIR/slam_nav.log"
echo "To stop: kill $RPLIDAR_PID $GMAPPING_PID $SLAM_NAV_PID"
