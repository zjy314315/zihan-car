with open('/home/jetson/recognition-api-master/car_intelligent_monitor.py', 'r') as f:
    c = f.read()

# 1. Fix _send_command_tcp - use button control format
old_start = c.find('    def _send_command_tcp(self, linear_x: float, angular_z: float) -> bool:')
old_end = c.find('\n    def _send_stop', old_start)

new_tcp = '''    def _send_command_tcp(self, linear_x: float, angular_z: float) -> bool:
        try:
            if linear_x > 0.15:
                direction = 1
            elif linear_x < -0.15:
                direction = 2
            elif angular_z < -0.15:
                direction = 5
            elif angular_z > 0.15:
                direction = 6
            else:
                direction = 0
            data = "%02X" % direction
            code = "0115" + "%02X" % (len(data)//2 + 2) + data
            csum = sum(int(code[i:i+2], 16) for i in range(0, len(code), 2)) % 256
            frame = "$" + code + ("%02X" % csum) + "#"
            car_ip = self._get_car_ip()
            print("[Formation] TCP send: %s -> direction=%d" % (frame, direction))
            with socket.create_connection((car_ip, 6000), timeout=0.5) as sock:
                sock.sendall(frame.encode())
            return True
        except Exception as e:
            print("[Formation] TCP failed: %s" % str(e))
            return False
'''

if old_start >= 0 and old_end >= 0:
    c = c[:old_start] + new_tcp + c[old_end:]
    print("1. TCP format fixed")

# 2. Add _get_car_ip if missing
if '_get_car_ip' not in c:
    ip_method = '''
    def _get_car_ip(self):
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            ip = s.getsockname()[0]
            s.close()
            return ip
        except:
            return "127.0.0.1"
'''
    pos = c.find('    def _init_ros(self):')
    c = c[:pos] + ip_method + '\n' + c[pos:]
    print("2. Added _get_car_ip")

# 3. Add debug print in _send_command
c = c.replace(
    '        if not self._send_command_ros(linear_x, angular_z):\n            self._send_command_tcp(linear_x, angular_z)',
    '        print("[Formation] PID: linear=%.3f angular=%.3f detect_only=%s" % (linear_x, angular_z, self.detect_only))\n        if not self.detect_only:\n            if not self._send_command_ros(linear_x, angular_z):\n                self._send_command_tcp(linear_x, angular_z)'
)
print("3. Added PID debug + detect_only guard")

with open('/home/jetson/recognition-api-master/car_intelligent_monitor.py', 'w') as f:
    f.write(c)
print("DONE")
