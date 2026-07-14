"""
Unit tests for udp_discovery.py.

Tests the UDP broadcast discovery service:
- WiFi IP extraction
- Car info JSON generation
- JSON schema validation
"""

import json
import sys
import os
import pytest
from unittest.mock import patch, MagicMock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from zihan_car_integration.udp_discovery import get_wifi_ip, get_car_info


class TestGetWifiIp:
    """Tests for the get_wifi_ip function."""

    @patch('subprocess.run')
    def test_extracts_10_dot_ip(self, mock_run):
        mock_result = MagicMock()
        mock_result.stdout = "10.168.202.242 192.168.0.1 \n"
        mock_result.returncode = 0
        mock_run.return_value = mock_result

        ip = get_wifi_ip()
        assert ip == "10.168.202.242" or ip.startswith("10.")

    @patch('subprocess.run')
    def test_extracts_192_168_ip(self, mock_run):
        mock_result = MagicMock()
        mock_result.stdout = "fe80::1 192.168.1.11 \n"
        mock_result.returncode = 0
        mock_run.return_value = mock_result

        ip = get_wifi_ip()
        assert ip.startswith("192.168.")

    @patch('subprocess.run')
    def test_prefers_10_dot_over_192(self, mock_run):
        mock_result = MagicMock()
        mock_result.stdout = "10.168.202.242 192.168.1.11 \n"
        mock_result.returncode = 0
        mock_run.return_value = mock_result

        ip = get_wifi_ip()
        # Should prefer 10. address (first match)
        assert ip == "10.168.202.242"

    @patch('subprocess.run')
    def test_fallback_when_no_matching_ip(self, mock_run):
        mock_result = MagicMock()
        mock_result.stdout = "172.17.0.1 fe80::1 \n"
        mock_result.returncode = 0
        mock_run.return_value = mock_result

        ip = get_wifi_ip()
        assert ip == "127.0.0.1"

    @patch('subprocess.run')
    def test_fallback_when_command_fails(self, mock_run):
        mock_run.side_effect = FileNotFoundError("hostname not found")

        ip = get_wifi_ip()
        assert ip == "127.0.0.1"

    @patch('subprocess.run')
    def test_fallback_when_empty_output(self, mock_run):
        mock_result = MagicMock()
        mock_result.stdout = ""
        mock_result.returncode = 0
        mock_run.return_value = mock_result

        ip = get_wifi_ip()
        assert ip == "127.0.0.1"


class TestGetCarInfo:
    """Tests for the get_car_info function."""

    @patch('zihan_car_integration.udp_discovery.get_wifi_ip')
    def test_returns_valid_json(self, mock_get_wifi):
        mock_get_wifi.return_value = "10.168.202.242"
        info = get_car_info()

        # Should be valid JSON
        parsed = json.loads(info)
        assert isinstance(parsed, dict)

    @patch('zihan_car_integration.udp_discovery.get_wifi_ip')
    def test_contains_all_required_fields(self, mock_get_wifi):
        mock_get_wifi.return_value = "192.168.1.11"
        info = get_car_info()
        parsed = json.loads(info)

        required_fields = ["name", "ip", "tcp_port", "monitor_port", "video_port"]
        for field in required_fields:
            assert field in parsed, f"Missing field: {field}"

    @patch('zihan_car_integration.udp_discovery.get_wifi_ip')
    def test_name_field(self, mock_get_wifi):
        mock_get_wifi.return_value = "10.0.0.1"
        parsed = json.loads(get_car_info())
        assert isinstance(parsed["name"], str)
        assert len(parsed["name"]) > 0

    @patch('zihan_car_integration.udp_discovery.get_wifi_ip')
    def test_ip_field(self, mock_get_wifi):
        expected_ip = "10.168.202.242"
        mock_get_wifi.return_value = expected_ip
        parsed = json.loads(get_car_info())
        assert parsed["ip"] == expected_ip

    @patch('zihan_car_integration.udp_discovery.get_wifi_ip')
    def test_tcp_port_is_integer(self, mock_get_wifi):
        mock_get_wifi.return_value = "10.0.0.1"
        parsed = json.loads(get_car_info())
        assert isinstance(parsed["tcp_port"], int)
        assert parsed["tcp_port"] > 0

    @patch('zihan_car_integration.udp_discovery.get_wifi_ip')
    def test_video_port_is_integer(self, mock_get_wifi):
        mock_get_wifi.return_value = "10.0.0.1"
        parsed = json.loads(get_car_info())
        assert isinstance(parsed["video_port"], int)
        assert parsed["video_port"] > 0

    @patch('zihan_car_integration.udp_discovery.get_wifi_ip')
    def test_monitor_port_is_integer(self, mock_get_wifi):
        mock_get_wifi.return_value = "10.0.0.1"
        parsed = json.loads(get_car_info())
        assert isinstance(parsed["monitor_port"], int)
        assert parsed["monitor_port"] > 0

    @patch('zihan_car_integration.udp_discovery.get_wifi_ip')
    def test_ports_are_reasonable_values(self, mock_get_wifi):
        mock_get_wifi.return_value = "10.0.0.1"
        parsed = json.loads(get_car_info())
        # Ports should be in valid range
        for port_key in ["tcp_port", "monitor_port", "video_port"]:
            port = parsed[port_key]
            assert 1 <= port <= 65535, \
                f"{port_key}={port} is out of valid port range"

    @patch('zihan_car_integration.udp_discovery.get_wifi_ip')
    def test_consistent_output(self, mock_get_wifi):
        mock_get_wifi.return_value = "10.0.0.1"
        info1 = get_car_info()
        info2 = get_car_info()
        assert info1 == info2

    @patch('zihan_car_integration.udp_discovery.get_wifi_ip')
    def test_json_encodes_to_utf8(self, mock_get_wifi):
        mock_get_wifi.return_value = "10.0.0.1"
        info = get_car_info()
        encoded = info.encode("utf-8")
        assert len(encoded) > 0
        # Verify round-trip
        decoded = json.loads(encoded.decode("utf-8"))
        assert decoded["name"] is not None


class TestUdpBroadcastSchema:
    """Tests validating the broadcast message schema against consumer expectations."""

    EXPECTED_SCHEMA = {
        "name": str,
        "ip": str,
        "tcp_port": int,
        "monitor_port": int,
        "video_port": int,
    }

    @patch('zihan_car_integration.udp_discovery.get_wifi_ip')
    def test_schema_types_match(self, mock_get_wifi):
        mock_get_wifi.return_value = "10.168.202.242"
        parsed = json.loads(get_car_info())

        for field, expected_type in self.EXPECTED_SCHEMA.items():
            assert isinstance(parsed[field], expected_type), \
                f"Field '{field}' should be {expected_type.__name__}, got {type(parsed[field]).__name__}"

    @patch('zihan_car_integration.udp_discovery.get_wifi_ip')
    def test_no_extra_unexpected_fields(self, mock_get_wifi):
        mock_get_wifi.return_value = "10.0.0.1"
        parsed = json.loads(get_car_info())
        expected_fields = set(self.EXPECTED_SCHEMA.keys())
        actual_fields = set(parsed.keys())
        assert actual_fields == expected_fields, \
            f"Extra fields: {actual_fields - expected_fields}"

    @patch('zihan_car_integration.udp_discovery.get_wifi_ip')
    def test_message_size_reasonable(self, mock_get_wifi):
        """UDP broadcast messages should not be too large."""
        mock_get_wifi.return_value = "10.0.0.1"
        info = get_car_info()
        assert len(info.encode('utf-8')) < 512, \
            "UDP broadcast message should be well under typical MTU"


class TestBroadcastConstants:
    """Tests for broadcast constants."""

    def test_broadcast_port(self):
        from zihan_car_integration.udp_discovery import BROADCAST_PORT
        assert BROADCAST_PORT == 9999

    def test_interval(self):
        from zihan_car_integration.udp_discovery import INTERVAL
        assert INTERVAL == 3
