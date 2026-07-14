#!/bin/bash
# 启动模式：加载已保存的地图 + AMCL 定位（替代 gmapping）
# 用法: bash start_saved_map.sh <地图名>
# 地图文件: ~/Rosmaster-App/rosmaster/maps/<地图名>.yaml

source /opt/ros/foxy/setup.bash
source /home/jetson/code/software/library_ws/install/setup.bash

MAP_NAME="${1:-saved_map}"
MAP_DIR="/home/jetson/Rosmaster-App/rosmaster/maps"
YAML="${MAP_DIR}/${MAP_NAME}.yaml"
PGM="${MAP_DIR}/${MAP_NAME}.pgm"
LOGDIR=/tmp/slam_logs
mkdir -p $LOGDIR

if [ ! -f "$YAML" ] || [ ! -f "$PGM" ]; then
  echo "ERROR: Map files not found at ${MAP_DIR}/${MAP_NAME}.{yaml,pgm}"
  echo "Available maps:"
  ls ${MAP_DIR}/*.yaml 2>/dev/null | sed 's/.*\///; s/\.yaml$//'
  exit 1
fi

echo "=== Loading saved map: ${MAP_NAME} ==="

# 1. RPLIDAR（必须）
echo "[1/4] Starting RPLIDAR..."
ros2 launch sllidar_ros2 sllidar_launch.py \
  serial_port:=/dev/rplidar serial_baudrate:=115200 frame_id:=laser \
  > $LOGDIR/rplidar.log 2>&1 &
sleep 3

# 2. map_server 加载已保存的地图
echo "[2/4] Loading map: ${MAP_NAME}..."
ros2 run nav2_map_server map_server --ros-args \
  -p yaml_filename:="${YAML}" \
  -p topic_name:="/map" \
  > $LOGDIR/map_server.log 2>&1 &
sleep 2

# 3. AMCL 定位（订阅激光 + map，发布 map→odom TF）
echo "[3/4] Starting AMCL localization..."
ros2 run nav2_amcl amcl --ros-args \
  -p base_frame_id:="base_link" \
  -p odom_frame_id:="odom" \
  -p scan_topic:="/scan" \
  -p set_initial_pose:=true \
  -p initial_pose_x:=0.0 \
  -p initial_pose_y:=0.0 \
  -p initial_pose_z:=0.0 \
  -p initial_pose_a:=0.0 \
  > $LOGDIR/amcl.log 2>&1 &
sleep 2

# 4. slam_nav_service（需要 map→odom TF，来自 AMCL）
echo "[4/4] Starting slam_nav_service (port 7000)..."
cd /home/jetson/Rosmaster-App/rosmaster
python3 slam_nav_service.py > $LOGDIR/slam_nav.log 2>&1 &
sleep 4

echo ""
echo "=== All services started (saved-map mode) ==="
echo "Map: ${MAP_NAME}"
echo "Logs: $LOGDIR/"
echo ""
echo "To check: curl http://localhost:7000/api/system/pose"
