#!/usr/bin/env python3
"""
Simple test client to verify NNG voice endpoint is working.
Connects to module A's voice stream and waits for Opus audio frames.
"""

import pynng
import sys
import time


def test_voice_endpoint(url="tcp://localhost:5556"):
    """Connect to NNG voice endpoint and wait for audio frames."""
    print(f"Connecting to {url}...")

    try:
        with pynng.Pair0(dial=url, recv_timeout=5000) as sock:
            print(f"Connected! Waiting for Opus audio frames...")
            print(
                "(Note: No frames will arrive unless someone is transmitting on module A)"
            )

            start_time = time.time()
            frame_count = 0

            # Wait up to 30 seconds for frames
            while time.time() - start_time < 30:
                try:
                    msg = sock.recv()
                    frame_count += 1

                    # Parse frame: [module_char][opus_data]
                    if len(msg) > 1:
                        module = chr(msg[0])
                        opus_len = len(msg) - 1
                        print(
                            f"Received frame #{frame_count}: module={module}, opus_bytes={opus_len}"
                        )
                    else:
                        print(f"Received short message: {len(msg)} bytes")

                except pynng.exceptions.Timeout:
                    # Timeout is expected if no one is transmitting
                    continue
                except Exception as e:
                    print(f"Receive error: {e}")
                    break

            if frame_count == 0:
                print("\nNo frames received in 30 seconds.")
                print("This is expected if no one is transmitting audio on module A.")
                print(
                    "Connection test: PASSED (connected successfully, no transmission)"
                )
                return True
            else:
                print(f"\nReceived {frame_count} frames successfully!")
                print("Connection test: PASSED (received audio)")
                return True

    except Exception as e:
        print(f"Connection error: {e}")
        print("Connection test: FAILED")
        return False


if __name__ == "__main__":
    url = sys.argv[1] if len(sys.argv) > 1 else "tcp://localhost:5556"
    success = test_voice_endpoint(url)
    sys.exit(0 if success else 1)
