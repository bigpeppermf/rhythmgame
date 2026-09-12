"""Hand report + the TRACKED/COASTING/LOST state machine.

Rule 3 from PROJECT_BRIEF: never silently emit a stale position as if it were
fresh. A coasting hand keeps reporting a position, but its confidence decays
and its state says so. The confidence field is what makes that honest.
"""
import time

TRACKED = "TRACKED"
COASTING = "COASTING"
LOST = "LOST"

COAST_SECONDS = 0.20


class HandReport:
    """One hand as it goes on the wire. See PROTOCOL.md."""

    def __init__(self, slot):
        self.slot = slot
        self.x = 0.5
        self.y = 0.5
        self.vx = 0.0
        self.vy = 0.0
        self.conf = 0.0
        self.state = LOST
        self._last_seen = 0.0

    def update(self, x, y, vx, vy, conf, now=None):
        now = time.perf_counter() if now is None else now
        self.x, self.y, self.vx, self.vy = x, y, vx, vy
        self.conf = conf
        self.state = TRACKED
        self._last_seen = now

    def coast(self, now=None):
        """No detection this frame. Hold position, decay confidence, and fall
        through to LOST once we have been guessing too long."""
        now = time.perf_counter() if now is None else now
        age = now - self._last_seen
        if age >= COAST_SECONDS:
            self.state = LOST
            self.conf = 0.0
            self.vx = self.vy = 0.0
        else:
            self.state = COASTING
            self.conf = max(0.0, self.conf * (1.0 - age / COAST_SECONDS))

    def to_dict(self):
        return {
            "slot": self.slot,
            "x": round(self.x, 4), "y": round(self.y, 4),
            "vx": round(self.vx, 3), "vy": round(self.vy, 3),
            "conf": round(self.conf, 3),
            "state": self.state,
        }
