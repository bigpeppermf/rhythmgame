"""Inspect the hand stream without Godot: python vision/udp_receiver.py."""

import argparse
import json
import socket
import sys
from time import monotonic, sleep

from udp_protocol import DEFAULT_HOST, DEFAULT_PORT, decode_packet, port_number


class UdpHandReceiver:
    """Single-producer diagnostic receiver; newest capture wins, not arrival order."""

    def __init__(self, host=DEFAULT_HOST, port=DEFAULT_PORT, timeout=0.5):
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            self.socket.bind((host, port))
            self.socket.setblocking(False)
        except OSError:
            self.socket.close()
            raise
        self.timeout = timeout
        self.latest = None
        self.last_received = None
        self.invalid_packets = 0

    def poll(self):
        # Bound work per poll so a busy sender cannot starve timeout/display work.
        for _ in range(256):
            try:
                data, _ = self.socket.recvfrom(65535)
            except BlockingIOError:
                break
            try:
                packet = decode_packet(data)
            except (ValueError, UnicodeError):
                self.invalid_packets += 1
                continue
            order = (packet["t_capture"], packet["seq"])
            if self.latest is None or order > (self.latest["t_capture"], self.latest["seq"]):
                self.latest = packet
                self.last_received = monotonic()
        if self.last_received is None or monotonic() - self.last_received >= self.timeout:
            return None
        return self.latest

    def close(self):
        self.socket.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bind", default=DEFAULT_HOST, help="Use 0.0.0.0 to receive over LAN")
    parser.add_argument("--port", type=port_number, default=DEFAULT_PORT)
    parser.add_argument("--json", action="store_true", help="Print full newest packets")
    args = parser.parse_args()
    receiver = UdpHandReceiver(args.bind, args.port)
    print(f"Listening on {args.bind}:{args.port}. Ctrl+C quits.", flush=True)
    last_display = float("-inf")
    try:
        while True:
            packet = receiver.poll()
            now = monotonic()
            if now - last_display >= 0.2:
                if packet is None:
                    text = "NO FRESH DATA: both hands unavailable (500 ms packet timeout)"
                elif args.json:
                    text = json.dumps(packet)
                else:
                    hands = sorted(packet["hands"], key=lambda hand: hand["slot"])
                    summaries = [
                        f"{name}: {hand['state']} y={hand['y']:.3f} conf={hand['conf']:.2f}"
                        + (f" gesture={hand['gesture']} ({hand['gesture_conf']:.2f})" if "gesture" in hand else "")
                        for name, hand in zip(("Left", "Right"), hands)
                    ]
                    text = f"seq={packet['seq']} fps={packet['fps']:.1f} | " + " | ".join(summaries)
                print(text, flush=True)
                last_display = now
            sleep(0.01)
    except KeyboardInterrupt:
        pass
    finally:
        receiver.close()


if __name__ == "__main__":
    try:
        main()
    except OSError as error:
        print(f"UDP receiver failed: {error}. Check the bind address/port; stop any other receiver.",
              file=sys.stderr)
        sys.exit(1)
