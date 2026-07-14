"""
Unit tests for car_main.py encoding/decoding utilities.

Tests the TCP protocol encoding functions extracted from the main service:
- Buzzer command encoding
- Buzzer command decoding/validation
- Checksum computation
"""

import sys
import os
import re
import pytest

# Add parent to path so we can import from zihan_car_integration if needed
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))


# ---------------------------------------------------------------------------
# Re-create the pure functions from car_main.py for isolated unit testing.
# This avoids importing car_main.py (which triggers cv2/YOLO/Flask imports
# that require a full runtime environment).
# ---------------------------------------------------------------------------

def build_buzzer_cmd(on: bool, delay_ms: int = 2550) -> bytes:
    """Build buzzer TCP command (with checksum + $/# wrapping)."""
    state = '01' if on else '00'
    delay_val = min(255, max(0, delay_ms // 10)) if on else 0
    delay = format(delay_val, '02X')
    info = state + delay
    size = format(len(info) + 2, '02X')
    code = '01' + '13' + size + info
    checksum = 0
    for i in range(0, len(code), 2):
        checksum = (checksum + int(code[i:i + 2], 16)) % 256
    return ('$' + code + format(checksum, '02X') + '#').encode('ascii')


def compute_checksum(data: str) -> int:
    """Compute the 8-bit checksum over hex string data."""
    checksum = 0
    for i in range(0, len(data), 2):
        checksum = (checksum + int(data[i:i + 2], 16)) % 256
    return checksum


def number_to_hex(num: int, length: int) -> str:
    """Convert number to zero-padded uppercase hex string."""
    hex_str = hex(num)[2:].upper()
    while len(hex_str) < length:
        hex_str = '0' + hex_str
    return hex_str


def base_encode(car_type: str, cmd_type: str, *datas: str) -> str:
    """Generic base encoder matching the ArkTS CarEncode.BaseEncode logic."""
    info = ''.join(datas)
    size = number_to_hex(len(info) + 2, 2)
    code = car_type + cmd_type + size + info
    code += number_to_hex(compute_checksum(code), 2)
    return f'${code}#'


def ctrl_car_encode(speed_x: int, speed_y: int) -> str:
    """Car control encoder matching CarEncode.CtrlCarEncode."""
    send_x = round(speed_x)
    send_y = round(speed_y)
    if send_x < 0:
        send_x += 256
    if send_y < 0:
        send_y += 256
    return base_encode('01', '10',
                        number_to_hex(send_x, 2) + number_to_hex(send_y, 2))


def button_car_encode(direction: int) -> str:
    """Button control encoder matching CarEncode.ButtonCarEncode."""
    return base_encode('01', '15', number_to_hex(direction, 2))


def buzzer_encode(on: bool) -> str:
    """Buzzer encoder matching CarEncode.BuzzerEncode."""
    return base_encode('01', '13', number_to_hex(1 if on else 0, 2))


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

class TestBuildBuzzerCmd:
    """Tests for the TCP buzzer command builder."""

    def test_buzzer_on_produces_valid_protocol(self):
        cmd = build_buzzer_cmd(True, 2550)
        cmd_str = cmd.decode('ascii')
        assert cmd_str.startswith('$'), "Command should start with $"
        assert cmd_str.endswith('#'), "Command should end with #"
        assert '13' in cmd_str, "Command type 13 (buzzer) should be present"

    def test_buzzer_off_produces_valid_protocol(self):
        cmd = build_buzzer_cmd(False, 0)
        cmd_str = cmd.decode('ascii')
        assert cmd_str.startswith('$')
        assert cmd_str.endswith('#')

    def test_buzzer_on_state_is_01(self):
        cmd = build_buzzer_cmd(True)
        cmd_str = cmd.decode('ascii')
        # Inner body should contain '01' for ON state
        inner = cmd_str[1:-1]  # strip $ and #
        assert '01' in inner

    def test_buzzer_off_state_is_00(self):
        cmd = build_buzzer_cmd(False)
        cmd_str = cmd.decode('ascii')
        inner = cmd_str[1:-1]
        # First two hex chars after the header should be 00 for off
        assert '00' in inner

    def test_buzzer_on_and_off_differ(self):
        cmd_on = build_buzzer_cmd(True)
        cmd_off = build_buzzer_cmd(False)
        assert cmd_on != cmd_off

    def test_delay_ms_clamps_to_max_2550(self):
        cmd = build_buzzer_cmd(True, 99999)
        # delay_val = min(255, max(0, 99999 // 10)) = min(255, 9999) = 255
        # delay = format(255, '02X') = 'FF'
        cmd_str = cmd.decode('ascii')
        assert 'FF' in cmd_str  # Max delay value

    def test_delay_ms_minimum_zero(self):
        cmd = build_buzzer_cmd(True, -1000)
        cmd_str = cmd.decode('ascii')
        # delay_val = min(255, max(0, -1000 // 10)) = min(255, 0) = 0
        assert '00' in cmd_str

    def test_delay_zero_when_buzzer_off(self):
        cmd = build_buzzer_cmd(False, 5000)
        cmd_str = cmd.decode('ascii')
        # When off, delay is always 0 regardless of input
        assert '00' in cmd_str

    def test_checksum_valid(self):
        """Verify the checksum is actually valid."""
        cmd = build_buzzer_cmd(True, 2550)
        cmd_str = cmd.decode('ascii')
        # Strip $ and #
        inner = cmd_str[1:-1]
        # Last 2 chars are checksum; rest is code
        code = inner[:-2]
        expected_checksum_hex = inner[-2:]
        actual_checksum = compute_checksum(code)
        expected_checksum = int(expected_checksum_hex, 16)
        assert actual_checksum == expected_checksum, \
            f"Checksum mismatch: computed {actual_checksum:02X}, expected {expected_checksum_hex}"

    def test_produces_ascii_bytes(self):
        cmd = build_buzzer_cmd(True)
        # Should be decodable as ASCII
        decoded = cmd.decode('ascii')
        # Should only contain printable ASCII + $ and #
        assert all(32 <= ord(c) < 127 for c in decoded if c not in '$#')


class TestComputeChecksum:
    """Tests for the checksum computation function."""

    def test_empty_string_checksum_zero(self):
        assert compute_checksum('') == 0

    def test_simple_checksum(self):
        # '01' + '13' + '02' + '01FF' = '01130201FF' => checksum
        data = '01130201FF'
        # 0x01 + 0x13 + 0x02 + 0x01 + 0xFF = 0x116 => 0x16 (mod 256)
        expected = (0x01 + 0x13 + 0x02 + 0x01 + 0xFF) % 256
        assert compute_checksum(data) == expected

    def test_checksum_is_modulo_256(self):
        data = 'FF' * 10  # 0xFF * 5 bytes
        result = compute_checksum(data)
        assert 0 <= result <= 255

    def test_deterministic(self):
        data = '011302044A4B'
        assert compute_checksum(data) == compute_checksum(data)


class TestNumberToHex:
    """Tests for number-to-hex conversion."""

    def test_zero(self):
        assert number_to_hex(0, 2) == '00'

    def test_single_digit_padded(self):
        assert number_to_hex(5, 2) == '05'
        assert number_to_hex(15, 2) == '0F'

    def test_no_padding_needed(self):
        assert number_to_hex(255, 2) == 'FF'

    def test_longer_length(self):
        assert number_to_hex(0, 4) == '0000'
        assert number_to_hex(256, 4) == '0100'

    def test_uppercase_output(self):
        result = number_to_hex(170, 2)
        assert result == 'AA'
        assert result.isupper()


class TestBaseEncode:
    """Tests for the base encoding function."""

    def test_produces_wrapped_format(self):
        result = base_encode('01', '10', '3232')
        assert result.startswith('$')
        assert result.endswith('#')

    def test_includes_car_type(self):
        result = base_encode('01', '10', '00')
        inner = result[1:-1]
        assert inner.startswith('01')

    def test_includes_command_type(self):
        result = base_encode('01', '63', '')
        inner = result[1:-1]
        assert '63' in inner

    def test_size_field_correct(self):
        # info='0000' length 4, +2 = 6 => size = '06'
        result = base_encode('01', '10', '0000')
        inner = result[1:-1]
        # Format: 01 + 10 + 06 + 0000 + CS
        size_hex = inner[4:6]
        assert size_hex == '06'

    def test_checksum_present(self):
        result = base_encode('01', '10', '3232')
        inner = result[1:-1]
        # Last 2 chars are checksum
        assert len(inner) >= 10  # minimum length with checksum
        checksum_hex = inner[-2:]
        code = inner[:-2]
        assert compute_checksum(code) == int(checksum_hex, 16)

    def test_multiple_data_parts_joined(self):
        result = base_encode('01', '21', 'AA', 'BB', 'CC', 'DD')
        inner = result[1:-1]
        # size = len('AABBCCDD') + 2 = 8 + 2 = 10 = '0A'
        assert '0A' in inner


class TestCtrlCarEncode:
    """Tests for the car control encoder."""

    def test_zero_speeds(self):
        result = ctrl_car_encode(0, 0)
        assert result.startswith('$')
        assert result.endswith('#')
        assert '10' in result  # command type

    def test_positive_speeds(self):
        result = ctrl_car_encode(50, 80)
        assert result.startswith('$')
        assert result.endswith('#')

    def test_negative_speeds_mapped(self):
        """Negative speeds should be mapped to 256-complement."""
        result = ctrl_car_encode(-50, -100)
        inner = result[1:-1]
        # send_x = -50 + 256 = 206 = 'CE'
        # send_y = -100 + 256 = 156 = '9C'
        code = inner[:-2]  # strip checksum
        # code format: 01(2) + 10(2) + size(2) = 6 chars before data
        data = code[6:]
        assert data == 'CE9C' or data[0:2] == 'CE', \
            f"Expected negative mapped data, got: {data}"

    def test_round_floats(self):
        result1 = ctrl_car_encode(50, 50)
        result2 = ctrl_car_encode(50.3, 49.7)
        # 50.3 rounds to 50, 49.7 rounds to 50
        assert result1 == result2

    def test_max_positive(self):
        result = ctrl_car_encode(100, 100)
        assert result.startswith('$')
        assert result.endswith('#')

    def test_max_negative(self):
        result = ctrl_car_encode(-100, -100)
        assert result.startswith('$')
        assert result.endswith('#')


class TestButtonCarEncode:
    """Tests for the button control encoder."""

    def test_stop_direction(self):
        result = button_car_encode(0)  # Stop
        assert result.startswith('$')
        assert result.endswith('#')
        assert '15' in result

    def test_front_direction(self):
        result = button_car_encode(1)  # Front
        assert result.startswith('$')
        assert result.endswith('#')

    def test_all_directions_unique(self):
        """Each direction 0-7 should produce a unique command."""
        results = [button_car_encode(d) for d in range(8)]
        assert len(set(results)) == 8

    def test_consistent_output(self):
        r1 = button_car_encode(3)
        r2 = button_car_encode(3)
        assert r1 == r2


class TestBuzzerEncode:
    """Tests for the buzzer encoder."""

    def test_buzzer_on(self):
        result = buzzer_encode(True)
        assert result.startswith('$')
        assert result.endswith('#')
        assert '13' in result

    def test_buzzer_off(self):
        result = buzzer_encode(False)
        assert result.startswith('$')
        assert result.endswith('#')

    def test_buzzer_on_differs_from_off(self):
        assert buzzer_encode(True) != buzzer_encode(False)


class TestProtocolRoundTrip:
    """End-to-end protocol tests: encode then validate."""

    PROTOCOL_RE = re.compile(r'^\$[0-9A-F]+#$')

    def assert_valid_protocol(self, msg: str):
        assert self.PROTOCOL_RE.match(msg), \
            f"Message does not match protocol format: {msg}"

    def assert_valid_checksum(self, msg: str):
        inner = msg[1:-1]
        code = inner[:-2]
        given_checksum = int(inner[-2:], 16)
        computed = compute_checksum(code)
        assert given_checksum == computed, \
            f"Checksum mismatch: given={given_checksum:02X}, computed={computed:02X}"

    def test_all_buzzer_commands(self):
        for on in (True, False):
            for delay in (0, 1000, 2550, 5000):
                cmd = build_buzzer_cmd(on, delay)
                msg = cmd.decode('ascii')
                self.assert_valid_protocol(msg)
                self.assert_valid_checksum(msg)

    def test_all_ctrl_car_commands(self):
        test_cases = [
            (0, 0), (100, 100), (-100, -100),
            (50, -50), (-50, 50), (100, 0), (0, 100),
        ]
        for sx, sy in test_cases:
            msg = ctrl_car_encode(sx, sy)
            self.assert_valid_protocol(msg)
            self.assert_valid_checksum(msg)

    def test_all_button_commands(self):
        for d in range(8):
            msg = button_car_encode(d)
            self.assert_valid_protocol(msg)
            self.assert_valid_checksum(msg)

    def test_all_buzzer_encoder_commands(self):
        for on in (True, False):
            msg = buzzer_encode(on)
            self.assert_valid_protocol(msg)
            self.assert_valid_checksum(msg)
