"""UDP emitter. Owns the wire format defined in PROTOCOL.md.

Fire and forget - no handshake, no acknowledgement, no retries. A dropped
packet is a stale frame; a resent packet is a late frame. Stale always beats
late, so nothing is ever resent.
"""
import json
import socket

PROTOCOL_VERSION = 1


class Emitter:
    def __init__(self, host="127.0.0.1", port=9000, enabled=True):
        self.addr = (host, port)
        self.enabled = enabled
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.seq = 0

    def send(self, hands, t_capture, fps):
        """hands: exactly 2 HandReport, slot 0 then slot 1.

        Always send both. A hand that is not visible is sent as LOST with
        conf 0, never omitted - a missing entry is a protocol error, not
        'no hand'.
        """
        assert len(hands) == 2, "protocol requires exactly 2 hands"
        self.seq += 1
        if not self.enabled:
            return
        payload = {
            "v": PROTOCOL_VERSION,
            "seq": self.seq,
            "t_capture": t_capture,
            "fps": round(fps, 2),
            "hands": [h.to_dict() for h in hands],
        }
        self.sock.sendto(json.dumps(payload).encode(), self.addr)

    def close(self):
        self.sock.close()
