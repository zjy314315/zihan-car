#!/usr/bin/env python3
"""
Lightweight lifecycle control for heavy Zihan Car project processes.

The TCP bridge stays resident as the small command entrypoint. App pages send
feature start/stop commands to it; this module starts only the process needed by
that page and stops it when no active page still needs it.
"""

import os
import signal
import subprocess
import time
from typing import Dict, List, Optional, Tuple


class ProjectProcessManager:
    def __init__(self, repo_dir: Optional[str] = None):
        self.repo_dir = repo_dir or os.environ.get(
            "ZIHAN_CAR_DIR",
            os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        )
        self.run_dir = os.environ.get("ZIHAN_CAR_RUN_DIR", "/tmp/zihan-car-lifecycle")
        os.makedirs(self.run_dir, exist_ok=True)
        self.active_features: Dict[str, int] = {}
        self.features: Dict[str, Dict[str, object]] = {
            "car_main": {
                "script": os.path.join(self.repo_dir, "zihan_car_integration", "car_main.py"),
                "cwd": os.path.join(self.repo_dir, "zihan_car_integration"),
                "pattern": "car_main.py",
            },
            "audio": {"alias": "car_main"},
            "video": {"alias": "car_main"},
            "vision": {"alias": "car_main"},
            "monitor": {
                "script": os.path.join(self.repo_dir, "zihan_car_integration", "car_intelligent_monitor.py"),
                "cwd": os.path.join(self.repo_dir, "zihan_car_integration"),
                "pattern": "car_intelligent_monitor.py",
            },
            "intelligent_monitor": {"alias": "monitor"},
            "dialogue": {
                "service": os.environ.get("ZIHAN_CAR_VOICE_SERVICE", "voice-assistant.service"),
            },
            # App/control are intentionally no-op here. A tiny bridge must stay
            # alive so the phone app can wake heavier feature processes.
            "app": {"noop": True},
            "control": {"noop": True},
        }

    def handle(self, action: str, feature: str) -> Dict[str, object]:
        action = (action or "").strip().lower()
        feature = (feature or "").strip().lower()
        if action not in ("start", "stop", "status", "stop_all"):
            return {"ok": False, "error": "unsupported action: %s" % action}

        try:
            if action == "stop_all":
                return self.stop_all()
            if action == "start":
                return self.start(feature)
            if action == "stop":
                return self.stop(feature)
            return self.status(feature)
        except Exception as exc:  # Keep bridge alive even if lifecycle fails.
            return {"ok": False, "feature": feature, "action": action, "error": str(exc)}

    def start(self, feature: str) -> Dict[str, object]:
        resolved = self._resolve(feature)
        if not resolved:
            return {"ok": False, "feature": feature, "error": "unknown feature"}
        canonical, spec = resolved
        self._retain(feature)

        if spec.get("noop"):
            return {"ok": True, "feature": feature, "target": canonical, "state": "noop"}
        if "service" in spec:
            return self._systemctl("start", str(spec["service"]), feature, canonical)

        existing = self._find_script_pids(str(spec["script"]))
        if existing:
            self._write_pidfile(canonical, existing)
            return {"ok": True, "feature": feature, "target": canonical, "state": "already_running", "pids": existing}

        script = str(spec["script"])
        if not os.path.exists(script):
            return {"ok": False, "feature": feature, "target": canonical, "error": "missing script: %s" % script}

        log_path = os.path.join(self.run_dir, "%s.log" % canonical)
        log = open(log_path, "ab", buffering=0)
        env = dict(os.environ)
        env["PYTHONUNBUFFERED"] = "1"
        proc = subprocess.Popen(
            ["/usr/bin/python3", script],
            cwd=str(spec["cwd"]),
            stdout=log,
            stderr=subprocess.STDOUT,
            start_new_session=True,
            env=env,
        )
        self._write_pidfile(canonical, [proc.pid])
        return {"ok": True, "feature": feature, "target": canonical, "state": "started", "pids": [proc.pid], "log": log_path}

    def stop(self, feature: str) -> Dict[str, object]:
        resolved = self._resolve(feature)
        if not resolved:
            return {"ok": False, "feature": feature, "error": "unknown feature"}
        canonical, spec = resolved
        self._release(feature)

        if self._target_still_needed(canonical):
            return {"ok": True, "feature": feature, "target": canonical, "state": "still_needed"}
        if spec.get("noop"):
            return {"ok": True, "feature": feature, "target": canonical, "state": "noop"}
        if "service" in spec:
            return self._systemctl("stop", str(spec["service"]), feature, canonical)

        pids = sorted(set(self._read_pidfile(canonical) + self._find_script_pids(str(spec["script"]))))
        stopped: List[int] = []
        for pid in pids:
            if pid == os.getpid():
                continue
            if self._terminate_pid(pid):
                stopped.append(pid)
        self._remove_pidfile(canonical)
        return {"ok": True, "feature": feature, "target": canonical, "state": "stopped", "pids": stopped}

    def stop_all(self) -> Dict[str, object]:
        self.active_features.clear()
        results: Dict[str, object] = {}
        for feature in ("dialogue", "monitor", "car_main"):
            resolved = self._resolve(feature)
            if not resolved:
                continue
            canonical, spec = resolved
            if "service" in spec:
                results[feature] = self._systemctl("stop", str(spec["service"]), feature, canonical)
            elif not spec.get("noop"):
                pids = sorted(set(self._read_pidfile(canonical) + self._find_script_pids(str(spec["script"]))))
                stopped = []
                for pid in pids:
                    if pid != os.getpid() and self._terminate_pid(pid):
                        stopped.append(pid)
                self._remove_pidfile(canonical)
                results[feature] = {"ok": True, "feature": feature, "target": canonical, "state": "stopped", "pids": stopped}
        return {"ok": True, "results": results}

    def status(self, feature: str) -> Dict[str, object]:
        resolved = self._resolve(feature)
        if not resolved:
            return {"ok": False, "feature": feature, "error": "unknown feature"}
        canonical, spec = resolved
        if spec.get("noop"):
            return {"ok": True, "feature": feature, "target": canonical, "state": "noop"}
        if "service" in spec:
            service = str(spec["service"])
            result = subprocess.run(["systemctl", "is-active", service], universal_newlines=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            return {"ok": True, "feature": feature, "target": canonical, "service": service, "state": result.stdout.strip()}
        pids = self._find_script_pids(str(spec["script"]))
        return {"ok": True, "feature": feature, "target": canonical, "running": bool(pids), "pids": pids}

    def _resolve(self, feature: str) -> Optional[Tuple[str, Dict[str, object]]]:
        canonical = feature
        spec = self.features.get(canonical)
        seen = set()
        while spec and "alias" in spec:
            alias = str(spec["alias"])
            if alias in seen:
                return None
            seen.add(alias)
            canonical = alias
            spec = self.features.get(canonical)
        if not spec:
            return None
        return canonical, spec

    def _retain(self, feature: str) -> None:
        # Idempotent per feature/page: repeated start from the same page must not
        # require multiple stop calls. Different features still share the target
        # safely through _target_still_needed().
        self.active_features[feature] = 1

    def _release(self, feature: str) -> None:
        self.active_features.pop(feature, None)

    def _target_still_needed(self, canonical: str) -> bool:
        for feature, count in self.active_features.items():
            if count <= 0:
                continue
            resolved = self._resolve(feature)
            if resolved and resolved[0] == canonical:
                return True
        return False

    def _find_script_pids(self, script: str) -> List[int]:
        target = os.path.realpath(script)
        target_dir = os.path.dirname(target)
        target_base = os.path.basename(target)
        pids: List[int] = []
        for name in os.listdir("/proc"):
            if not name.isdigit():
                continue
            pid = int(name)
            if pid <= 1:
                continue
            cmdline_path = os.path.join("/proc", name, "cmdline")
            cwd_path = os.path.join("/proc", name, "cwd")
            try:
                with open(cmdline_path, "rb") as handle:
                    parts = [p.decode("utf-8", "ignore") for p in handle.read().split(b"\0") if p]
                cwd = os.path.realpath(os.readlink(cwd_path))
            except (OSError, IOError):
                continue
            if not parts or not os.path.basename(parts[0]).startswith("python"):
                continue
            for arg in parts[1:]:
                if not arg.endswith(".py"):
                    continue
                candidate = arg if os.path.isabs(arg) else os.path.join(cwd, arg)
                candidate = os.path.realpath(candidate)
                if candidate == target or (os.path.basename(candidate) == target_base and os.path.realpath(cwd) == target_dir):
                    pids.append(pid)
                    break
        return pids

    def _pidfile(self, feature: str) -> str:
        safe = "".join(ch if ch.isalnum() or ch in ("-", "_") else "_" for ch in feature)
        return os.path.join(self.run_dir, "%s.pids" % safe)

    def _write_pidfile(self, feature: str, pids: List[int]) -> None:
        with open(self._pidfile(feature), "w", encoding="utf-8") as handle:
            handle.write("\n".join(str(pid) for pid in pids))

    def _read_pidfile(self, feature: str) -> List[int]:
        path = self._pidfile(feature)
        if not os.path.exists(path):
            return []
        pids: List[int] = []
        with open(path, "r", encoding="utf-8") as handle:
            for line in handle:
                try:
                    pids.append(int(line.strip()))
                except ValueError:
                    pass
        return pids

    def _remove_pidfile(self, feature: str) -> None:
        try:
            os.unlink(self._pidfile(feature))
        except FileNotFoundError:
            pass

    def _terminate_pid(self, pid: int) -> bool:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            return False
        except PermissionError:
            subprocess.run(["kill", "-TERM", str(pid)], check=False)
        deadline = time.time() + 3
        while time.time() < deadline:
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                return True
            time.sleep(0.1)
        subprocess.run(["kill", "-KILL", str(pid)], check=False)
        return True

    def _systemctl(self, action: str, service: str, feature: str, canonical: str) -> Dict[str, object]:
        result = subprocess.run(["systemctl", action, service], universal_newlines=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return {
            "ok": result.returncode == 0,
            "feature": feature,
            "target": canonical,
            "service": service,
            "action": action,
            "returncode": result.returncode,
            "stderr": result.stderr.strip(),
        }
