"""JSON observations over UDP. No camera, model, or game dependencies."""

import json
from math import isfinite
import socket

DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 5005


def port_number(value):
    port = int(value)
    if not 1 <= port <= 65535:
        raise ValueError("Port must be between 1 and 65535.")
    return port


def build_packet(seq, t_capture, fps, hands):
    packet = {
        "seq": seq,
        "t_capture": t_capture,
        "fps": fps,
        "hands": [
            {"slot": hand.slot, "x": hand.position[0], "y": hand.position[1],
             "vx": hand.velocity[0], "vy": hand.velocity[1],
             "conf": hand.confidence, "state": hand.state}
            for hand in hands
        ],
    }
    validate_packet(packet)
    return packet


def validate_packet(packet):
    """Validate the shared v1 fields; additional fields may be ignored."""
    def number(value):
        return type(value) in (int, float) and isfinite(value)

    if not isinstance(packet, dict):
        raise ValueError("Packet must be a JSON object.")
    if type(packet.get("seq")) is not int or packet["seq"] < 0:
        raise ValueError("seq must be a nonnegative integer.")
    if not number(packet.get("t_capture")) or packet["t_capture"] < 0:
        raise ValueError("t_capture must be finite monotonic seconds.")
    if not number(packet.get("fps")) or packet["fps"] < 0:
        raise ValueError("fps must be finite and nonnegative.")
    hands = packet.get("hands")
    if not isinstance(hands, list) or len(hands) != 2:
        raise ValueError("Packet must contain both hand slots.")
    slots = []
    for hand in hands:
        if not isinstance(hand, dict) or type(hand.get("slot")) is not int:
            raise ValueError("Invalid hand slot.")
        slots.append(hand["slot"])
        if hand.get("state") not in ("TRACKED", "COASTING", "LOST"):
            raise ValueError("Unknown tracking state.")
        for key in ("x", "y", "vx", "vy", "conf"):
            if not number(hand.get(key)):
                raise ValueError(f"{key} must be finite.")
        if not all(0 <= hand[key] <= 1 for key in ("x", "y", "conf")):
            raise ValueError("x/y/conf must be normalized to [0,1].")
        if hand["state"] == "LOST" and hand["conf"] != 0:
            raise ValueError("LOST observations must have zero confidence.")
    if sorted(slots) != [0, 1]:
        raise ValueError("Expected distinct slots 0 and 1.")


def decode_packet(data):
    packet = json.loads(data.decode("utf-8"))
    validate_packet(packet)
    return packet


class UdpHandSender:
    """Send each snapshot once, without waiting or retrying old observations."""

    def __init__(self, host=DEFAULT_HOST, port=DEFAULT_PORT):
        # Resolve once at startup, not during the camera loop.
        self.destination = (socket.gethostbyname(host), port_number(port))
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.socket.setblocking(False)
        self.seq = 0
        self.dropped = 0
        self.last_error = None

    def send(self, hands, t_capture, fps):
        packet = build_packet(self.seq, t_capture, fps, hands)
        data = json.dumps(packet, allow_nan=False, separators=(",", ":")).encode("utf-8")
        self.seq += 1  # Includes failed attempts so gaps remain visible.
        try:
            self.socket.sendto(data, self.destination)
        except OSError as error:
            self.dropped += 1
            self.last_error = str(error)
            return False
        self.last_error = None
        return True  # Queued locally; UDP does not confirm delivery.

    def close(self):
        self.socket.close()
