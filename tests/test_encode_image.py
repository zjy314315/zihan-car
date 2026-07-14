"""
Unit tests for encode_image.py.

Tests the image-to-base64 encoding utility.
"""

import sys
import os
import base64
import pytest
from unittest.mock import patch, mock_open

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from zihan_car_integration.encode_image import image_to_base64


class TestImageToBase64:
    """Tests for the image_to_base64 function."""

    def test_encodes_valid_image(self):
        """Test that a valid image file is properly encoded."""
        fake_image_data = b'\x89PNG\r\n\x1a\n' + b'\x00' * 100  # PNG header
        expected_base64 = base64.b64encode(fake_image_data).decode('utf-8')

        with patch('os.path.exists', return_value=True):
            with patch('builtins.open', mock_open(read_data=fake_image_data)):
                result = image_to_base64('/fake/path/image.png')
                assert result == expected_base64

    @patch('os.path.exists', return_value=False)
    def test_returns_none_for_missing_file(self, mock_exists):
        result = image_to_base64('/nonexistent/image.jpg')
        assert result is None

    @patch('os.path.exists', return_value=True)
    def test_returns_none_for_read_error(self, mock_exists):
        with patch('builtins.open', side_effect=PermissionError("Access denied")):
            result = image_to_base64('/fake/protected.jpg')
            assert result is None

    def test_encodes_empty_file(self):
        with patch('os.path.exists', return_value=True):
            with patch('builtins.open', mock_open(read_data=b'')):
                result = image_to_base64('/fake/empty.png')
                assert result == ''

    def test_encodes_binary_data_correctly(self):
        """Test that binary data round-trips through base64 encoding."""
        binary_data = bytes(range(256))  # All byte values 0-255
        with patch('os.path.exists', return_value=True):
            with patch('builtins.open', mock_open(read_data=binary_data)):
                result = image_to_base64('/fake/all_bytes.bin')
                assert result is not None
                # Verify round-trip
                decoded = base64.b64decode(result)
                assert decoded == binary_data

    def test_returns_string_type(self):
        with patch('os.path.exists', return_value=True):
            with patch('builtins.open', mock_open(read_data=b'test data')):
                result = image_to_base64('/fake/test.png')
                assert isinstance(result, str)

    def test_base64_string_is_valid(self):
        """Verify the output is valid base64."""
        test_data = b'Hello, World!'
        with patch('os.path.exists', return_value=True):
            with patch('builtins.open', mock_open(read_data=test_data)):
                result = image_to_base64('/fake/hello.png')
                assert result is not None
                # Decoding should succeed
                decoded = base64.b64decode(result)
                assert decoded == test_data

    def test_large_file_encoding(self):
        """Test encoding a moderately large file."""
        large_data = b'A' * 100000  # 100KB
        with patch('os.path.exists', return_value=True):
            with patch('builtins.open', mock_open(read_data=large_data)):
                result = image_to_base64('/fake/large.bin')
                assert result is not None
                assert len(result) == len(base64.b64encode(large_data).decode('utf-8'))
                # Round-trip verification
                assert base64.b64decode(result) == large_data
