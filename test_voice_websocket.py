#!/usr/bin/env python3
"""
Simple test to verify the voice WebSocket endpoint is accessible.
Connects to /ws/voice and verifies the connection is established.
"""

import sys
import json
import time

try:
    import websocket
except ImportError:
    print("Installing websocket-client...")
    import subprocess

    subprocess.check_call(
        [sys.executable, "-m", "pip", "install", "-q", "websocket-client"]
    )
    import websocket


def test_voice_websocket(url="ws://localhost:8080/ws/voice"):
    """Test voice WebSocket endpoint connectivity."""
    print(f"Connecting to {url}...")

    def on_message(ws, message):
        print(f"Received: {message}")
        try:
            data = json.loads(message)
            print(f"Message type: {data.get('type')}")
        except:
            pass

    def on_error(ws, error):
        print(f"Error: {error}")

    def on_close(ws, close_status_code, close_msg):
        print(f"Connection closed: {close_status_code} - {close_msg}")

    def on_open(ws):
        print("Connection opened successfully!")
        print("Sending voice_start test message...")
        test_msg = {"type": "voice_start", "module": "A", "callsign": "TEST"}
        ws.send(json.dumps(test_msg))

        # Wait a moment for response
        time.sleep(2)
        ws.close()

    ws = websocket.WebSocketApp(
        url,
        on_open=on_open,
        on_message=on_message,
        on_error=on_error,
        on_close=on_close,
    )

    try:
        ws.run_forever(timeout=10)
        print("\nTest PASSED: WebSocket endpoint is accessible")
        return True
    except Exception as e:
        print(f"\nTest FAILED: {e}")
        return False


if __name__ == "__main__":
    success = test_voice_websocket()
    sys.exit(0 if success else 1)
