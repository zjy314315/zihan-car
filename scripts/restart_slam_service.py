#!/usr/bin/env python3
"""Restart slam_nav_service cleanly and verify."""
import paramiko, time, sys

def ssh(cmd):
    stdin, stdout, stderr = client.exec_command(cmd)
    r = stdout.read().decode()
    e = stderr.read().decode()
    if r.strip(): print(r[:800])
    if e.strip(): print("ERR:", e[:300])

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('10.168.202.242', username='jetson', password='yahboom', timeout=10)

# 1. Kill ALL slam_nav processes
print("=== Killing all slam_nav_service ===")
ssh("pkill -f slam_nav_service 2>/dev/null; sleep 2; ps aux | grep slam_nav | grep -v grep || echo '(none)'")

# 2. Verify port 7000 is free
print("\n=== Port 7000 ===")
ssh("ss -tlnp 2>/dev/null | grep 7000 || echo 'port 7000 free'")

# 3. Check the patch is in the file
print("\n=== Verify patch in file ===")
ssh("grep -n 'silent=True\\|isinstance' ~/Rosmaster-App/rosmaster/slam_nav_service.py")

# 4. OPTIONS preflight check
print("\n=== OPTIONS preflight test ===")
ssh("""
curl -s -D- -X OPTIONS http://localhost:7000/api/map/build/end \\
  -H 'Origin: null' \\
  -H 'Access-Control-Request-Method: POST' \\
  -H 'Access-Control-Request-Headers: content-type' 2>&1 | head -20
""")

# 5. Start fresh
print("\n=== Starting slam_nav_service ===")
ssh("""
source /opt/ros/foxy/setup.bash
source ~/code/software/library_ws/install/setup.bash
cd ~/Rosmaster-App/rosmaster
python3 slam_nav_service.py > /tmp/slam_logs/slam_nav.log 2>&1 &
echo "PID: $!"
""")
time.sleep(5)

# 6. Test API
print("\n=== API test ===")
ssh("""
curl -s http://localhost:7000/api/system/ping
echo ""
curl -s -X POST http://localhost:7000/api/map/build/start
echo ""
""")

# 7. Test build/end from localhost (car side)
print("\n=== build/end test from localhost ===")
ssh("curl -s -X POST http://localhost:7000/api/map/build/end -H 'Content-Type: application/json' -d '{}'")

client.close()
