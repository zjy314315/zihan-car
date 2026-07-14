#!/usr/bin/env python3
"""Global lifecycle control for Zihan Car backend processes.

The app owns only two backend lifecycle events now:
- app startup sends start_all, which runs start_car.sh
- app shutdown/background sends stop_all, which runs stop_car.sh

Per-page feature start/stop commands are intentionally ignored so navigating
between app pages cannot start or kill backend processes or ports.
"""

import os
import subprocess
import time
from typing import Dict, Optional


class ProjectProcessManager:
    def __init__(self, repo_dir: Optional[str] = None):
        backend_dir = os.environ.get("ZIHAN_CAR_BACKEND_DIR", "/home/jetson/recognition-api-master")
        self.repo_dir = repo_dir or backend_dir
        self.start_script = os.environ.get("ZIHAN_CAR_START_SCRIPT", os.path.join(backend_dir, "start_car.sh"))
        self.stop_script = os.environ.get("ZIHAN_CAR_STOP_SCRIPT", os.path.join(backend_dir, "stop_car.sh"))
        self.timeout_seconds = int(os.environ.get("ZIHAN_CAR_LIFECYCLE_TIMEOUT", "120"))
        self.last_start_at = 0.0
        self.last_stop_at = 0.0

    def handle(self, action: str, feature: str) -> Dict[str, object]:
        action = (action or "").strip().lower()
        feature = (feature or "").strip().lower()

        try:
            if action == "start_all":
                return self.start_all()
            if action == "stop_all":
                return self.stop_all()
            if action == "status":
                return self.status(feature)
            if action in ("start", "stop"):
                return {
                    "ok": True,
                    "feature": feature,
                    "action": action,
                    "state": "ignored",
                    "message": "global lifecycle is controlled by start_all/stop_all",
                }
            return {"ok": False, "error": "unsupported action: %s" % action}
        except Exception as exc:
            return {"ok": False, "feature": feature, "action": action, "error": str(exc)}

    def start_all(self) -> Dict[str, object]:
        result = self._run_script("start_all", self.start_script)
        if result.get("ok"):
            self.last_start_at = time.time()
        return result

    def stop_all(self) -> Dict[str, object]:
        result = self._run_script("stop_all", self.stop_script)
        if result.get("ok"):
            self.last_stop_at = time.time()
        return result

    def status(self, feature: str = "all") -> Dict[str, object]:
        return {
            "ok": True,
            "feature": feature or "all",
            "mode": "global",
            "start_script": self.start_script,
            "stop_script": self.stop_script,
            "start_script_exists": os.path.exists(self.start_script),
            "stop_script_exists": os.path.exists(self.stop_script),
            "last_start_at": self.last_start_at,
            "last_stop_at": self.last_stop_at,
        }

    def _run_script(self, action: str, script: str) -> Dict[str, object]:
        if not os.path.exists(script):
            return {"ok": False, "action": action, "script": script, "error": "script not found"}

        result = subprocess.run(
            ["bash", script],
            cwd=os.path.dirname(script),
            universal_newlines=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=self.timeout_seconds,
        )
        return {
            "ok": result.returncode == 0,
            "action": action,
            "script": script,
            "returncode": result.returncode,
            "stdout": result.stdout.strip()[-2000:],
            "stderr": result.stderr.strip()[-2000:],
        }
