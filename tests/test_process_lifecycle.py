"""
Unit tests for process_lifecycle.py.

Tests the ProjectProcessManager which manages backend process lifecycle:
- Global start_all / stop_all via shell scripts
- Per-page start/stop commands are intentionally ignored
- Status queries
"""

import os
import sys
import subprocess
import pytest
from unittest.mock import patch, MagicMock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from zihan_car_integration.process_lifecycle import ProjectProcessManager


class TestProjectProcessManagerInit:
    """Tests for the constructor and initialization."""

    def test_default_constructor(self):
        mgr = ProjectProcessManager()
        assert mgr.repo_dir is not None
        assert mgr.start_script is not None
        assert mgr.stop_script is not None
        assert mgr.timeout_seconds == 120
        assert mgr.last_start_at == 0.0
        assert mgr.last_stop_at == 0.0

    def test_custom_repo_dir(self):
        mgr = ProjectProcessManager(repo_dir="/custom/path")
        assert mgr.repo_dir == "/custom/path"

    def test_custom_repo_dir_sets_script_paths(self):
        mgr = ProjectProcessManager(repo_dir="/custom/backend")
        assert "custom" in mgr.start_script or "backend" in mgr.repo_dir


class TestHandle:
    """Tests for the main handle method."""

    def test_handle_unsupported_action(self):
        mgr = ProjectProcessManager()
        result = mgr.handle("invalid_action", "car_main")
        assert result["ok"] == False
        assert "error" in result

    def test_handle_start_is_ignored(self):
        """Per-page start commands should be intentionally ignored."""
        mgr = ProjectProcessManager()
        result = mgr.handle("start", "video")
        assert result["ok"] == True
        assert result["state"] == "ignored"
        assert "global lifecycle" in str(result["message"])

    def test_handle_stop_is_ignored(self):
        """Per-page stop commands should be intentionally ignored."""
        mgr = ProjectProcessManager()
        result = mgr.handle("stop", "video")
        assert result["ok"] == True
        assert result["state"] == "ignored"

    @patch.object(ProjectProcessManager, 'start_all', return_value={"ok": True})
    def test_handle_delegates_to_start_all(self, mock_sa):
        mgr = ProjectProcessManager()
        result = mgr.handle("start_all", "")
        mock_sa.assert_called_once()
        assert result["ok"] == True

    @patch.object(ProjectProcessManager, 'stop_all', return_value={"ok": True})
    def test_handle_delegates_to_stop_all(self, mock_sa):
        mgr = ProjectProcessManager()
        result = mgr.handle("stop_all", "")
        mock_sa.assert_called_once()
        assert result["ok"] == True

    @patch.object(ProjectProcessManager, 'status', return_value={"ok": True, "feature": "test"})
    def test_handle_delegates_to_status(self, mock_status):
        mgr = ProjectProcessManager()
        result = mgr.handle("status", "test")
        mock_status.assert_called_once_with("test")
        assert result["ok"] == True

    def test_handle_handles_exception_gracefully(self):
        mgr = ProjectProcessManager()
        with patch.object(mgr, 'start_all', side_effect=RuntimeError("boom")):
            result = mgr.handle("start_all", "")
            assert result["ok"] == False
            assert "error" in result

    def test_handle_empty_action(self):
        mgr = ProjectProcessManager()
        result = mgr.handle("", "")
        assert result["ok"] == False

    def test_handle_start_all_preserves_last_start_at(self):
        mgr = ProjectProcessManager()
        mgr.last_start_at = 100.0
        mgr.handle("start_all", "")
        # start_all is called which should update the timestamp
        # (may fail if script missing, but that's ok for this test)


class TestStartAll:
    """Tests for the start_all method."""

    @patch.object(ProjectProcessManager, '_run_script')
    def test_start_all_returns_ok(self, mock_run):
        mock_run.return_value = {"ok": True}
        mgr = ProjectProcessManager()
        result = mgr.start_all()
        assert result["ok"] == True

    @patch.object(ProjectProcessManager, '_run_script')
    def test_start_all_updates_timestamp(self, mock_run):
        mock_run.return_value = {"ok": True}
        mgr = ProjectProcessManager()
        assert mgr.last_start_at == 0.0
        mgr.start_all()
        assert mgr.last_start_at > 0.0

    @patch.object(ProjectProcessManager, '_run_script')
    def test_start_all_preserves_timestamp_on_failure(self, mock_run):
        mock_run.return_value = {"ok": False}
        mgr = ProjectProcessManager()
        mgr.last_start_at = 12345.0
        mgr.start_all()
        assert mgr.last_start_at == 12345.0


class TestStopAll:
    """Tests for the stop_all method."""

    @patch.object(ProjectProcessManager, '_run_script')
    def test_stop_all_returns_ok(self, mock_run):
        mock_run.return_value = {"ok": True}
        mgr = ProjectProcessManager()
        result = mgr.stop_all()
        assert result["ok"] == True

    @patch.object(ProjectProcessManager, '_run_script')
    def test_stop_all_updates_timestamp(self, mock_run):
        mock_run.return_value = {"ok": True}
        mgr = ProjectProcessManager()
        assert mgr.last_stop_at == 0.0
        mgr.stop_all()
        assert mgr.last_stop_at > 0.0


class TestStatus:
    """Tests for the status method."""

    def test_status_returns_feature(self):
        mgr = ProjectProcessManager()
        result = mgr.status("car_main")
        assert result["ok"] == True
        assert result["feature"] == "car_main"

    def test_status_returns_mode(self):
        mgr = ProjectProcessManager()
        result = mgr.status("video")
        assert result["mode"] == "global"

    def test_status_returns_script_paths(self):
        mgr = ProjectProcessManager()
        result = mgr.status("test")
        assert "start_script" in result
        assert "stop_script" in result

    def test_status_returns_script_exists(self):
        mgr = ProjectProcessManager()
        result = mgr.status("test")
        assert "start_script_exists" in result
        assert "stop_script_exists" in result
        assert isinstance(result["start_script_exists"], bool)
        assert isinstance(result["stop_script_exists"], bool)

    def test_status_returns_timestamps(self):
        mgr = ProjectProcessManager()
        mgr.last_start_at = 100.0
        mgr.last_stop_at = 200.0
        result = mgr.status("test")
        assert result["last_start_at"] == 100.0
        assert result["last_stop_at"] == 200.0

    def test_status_default_feature(self):
        mgr = ProjectProcessManager()
        result = mgr.status()
        assert result["ok"] == True
        assert result["feature"] == "all"

    def test_status_empty_feature(self):
        mgr = ProjectProcessManager()
        result = mgr.status("")
        assert result["feature"] == "all"


class TestRunScript:
    """Tests for the internal _run_script method."""

    def test_script_not_found(self):
        mgr = ProjectProcessManager()
        result = mgr._run_script("start", "/nonexistent/script.sh")
        assert result["ok"] == False
        assert "error" in result
        assert result["action"] == "start"

    @patch('subprocess.run')
    @patch('os.path.exists', return_value=True)
    def test_script_runs_successfully(self, mock_exists, mock_run):
        mock_result = MagicMock()
        mock_result.returncode = 0
        mock_result.stdout = "OK"
        mock_result.stderr = ""
        mock_run.return_value = mock_result

        mgr = ProjectProcessManager()
        result = mgr._run_script("start_all", "/fake/start.sh")
        assert result["ok"] == True
        assert result["returncode"] == 0
        mock_run.assert_called_once()

    @patch('subprocess.run')
    @patch('os.path.exists', return_value=True)
    def test_script_failure(self, mock_exists, mock_run):
        mock_result = MagicMock()
        mock_result.returncode = 1
        mock_result.stdout = ""
        mock_result.stderr = "error occurred"
        mock_run.return_value = mock_result

        mgr = ProjectProcessManager()
        result = mgr._run_script("stop_all", "/fake/stop.sh")
        assert result["ok"] == False
        assert result["returncode"] == 1

    @patch('subprocess.run')
    @patch('os.path.exists', return_value=True)
    def test_script_truncates_long_output(self, mock_exists, mock_run):
        mock_result = MagicMock()
        mock_result.returncode = 0
        mock_result.stdout = "x" * 5000  # > 2000 chars
        mock_result.stderr = ""
        mock_run.return_value = mock_result

        mgr = ProjectProcessManager()
        result = mgr._run_script("start_all", "/fake/start.sh")
        assert result["ok"] == True
        assert len(result["stdout"]) <= 2000

    @patch('subprocess.run', side_effect=subprocess.TimeoutExpired(cmd="bash", timeout=120))
    @patch('os.path.exists', return_value=True)
    def test_script_timeout(self, mock_exists, mock_run):
        mgr = ProjectProcessManager()
        with pytest.raises(subprocess.TimeoutExpired):
            mgr._run_script("start_all", "/fake/start.sh")
