"""Optional camera self-view, streamed to the game on its own socket.

Separate from the hand data on purpose. Hand observations have a latency
budget; a JPEG does not. Keeping them apart means the preview can be slow,
lossy, or absent without ever delaying the signal the game is judged on.

Send the hand packet FIRST each frame, then call maybe_send() with whatever
time is left over.

Wire format: one datagram, raw JPEG bytes, no header. Newest wins; there is
nothing to reassemble and nothing to acknowledge. A dropped preview frame is
invisible, which is the correct level of care for a mirror.
"""
import socket
import time

import cv2

DEFAULT_PORT = 5006
# Small enough that a frame is a few KB and encodes in about a millisecond.
# This is a mirror, not a viewfinder - legibility beats fidelity.
DEFAULT_WIDTH = 224
DEFAULT_QUALITY = 55
DEFAULT_FPS = 15.0
# Loopback takes far larger, but staying under a typical MTU means this also
# works unchanged if the two halves ever run on different machines.
MAX_DATAGRAM = 60000


class PreviewSender:
    def __init__(self, host="127.0.0.1", port=DEFAULT_PORT, width=DEFAULT_WIDTH,
                 quality=DEFAULT_QUALITY, fps=DEFAULT_FPS):
        self.destination = (socket.gethostbyname(host), int(port))
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.socket.setblocking(False)
        self.width = int(width)
        self.quality = int(quality)
        self.period = 1.0 / float(fps) if fps > 0 else 0.0
        self.sent = 0
        self.dropped = 0
        self.encode_ms = 0.0
        self._last = float("-inf")

    def maybe_send(self, frame, now=None):
        """Throttled. Returns True if a frame went out this call."""
        now = time.perf_counter() if now is None else now
        if self.period and now - self._last < self.period:
            return False
        self._last = now

        h, w = frame.shape[:2]
        if w > self.width:
            scale = self.width / float(w)
            frame = cv2.resize(frame, (self.width, max(1, round(h * scale))),
                               interpolation=cv2.INTER_AREA)

        started = time.perf_counter()
        ok, buf = cv2.imencode(".jpg", frame,
                               [int(cv2.IMWRITE_JPEG_QUALITY), self.quality])
        self.encode_ms = (time.perf_counter() - started) * 1000.0
        if not ok or buf.size > MAX_DATAGRAM:
            self.dropped += 1
            return False
        try:
            self.socket.sendto(buf.tobytes(), self.destination)
        except OSError:
            # Nobody listening, or the buffer is full. Neither is worth
            # interrupting the camera loop over.
            self.dropped += 1
            return False
        self.sent += 1
        return True

    def close(self):
        self.socket.close()
