#!/usr/bin/env python3
"""轻量 UDP 发现服务 — 定时广播小车信息，手机 App 扫描接收"""
import socket
import json
import time
import subprocess

BROADCAST_PORT = 9999
INTERVAL = 3  # seconds between broadcasts

def get_wifi_ip():
    try:
        result = subprocess.run(["hostname", "-I"], capture_output=True, text=True)
        for ip in result.stdout.strip().split():
            if ip.startswith("10.") or ip.startswith("192.168."):
                return ip
    except:
        pass
    return "127.0.0.1"

def get_car_info():
    return json.dumps({
        "name": "iCar-智慧小车",
        "ip": get_wifi_ip(),
        "tcp_port": 6001,
        "monitor_port": 5001,
        "video_port": 5000,
    })

def main():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    print(f"[UDP] 广播发现服务已启动，每{INTERVAL}秒广播到 port {BROADCAST_PORT}")

    while True:
        try:
            info = get_car_info()
            # Broadcast to local network
            sock.sendto(info.encode("utf-8"), ("255.255.255.255", BROADCAST_PORT))
            print(f"[UDP] 广播: {info}")
        except Exception as e:
            print(f"[UDP] 广播失败: {e}")
        time.sleep(INTERVAL)

if __name__ == "__main__":
    main()
