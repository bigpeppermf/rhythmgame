"""Persistent hand observations, independent of MediaPipe, display, and UDP."""

from dataclasses import dataclass, replace
from math import isfinite
from typing import Literal


LOSS_TIMEOUT = 0.2  # Seconds since the last accepted capture, not frame count.
Position = tuple[float, float]


@dataclass(frozen=True)
class HandState:
    slot: int
    position: Position = (0.5, 0.5)  # Placeholder until first detection.
    velocity: Position = (0.0, 0.0)
    last_seen: float | None = None
    state: Literal["TRACKED", "COASTING", "LOST"] = "LOST"
    confidence: float = 0.0  # Usability weight, not a model probability.


class HandStateTracker: 
    """Consume two accepted positions (or None) using monotonic capture seconds.

    Always returns two immutable snapshots in anatomical left/right order.
    The detector owns validity/association; this layer owns age and velocity.
    """

    def __init__(self):
        self.hands = (HandState(slot=0), HandState(slot=1))
        self.last_update = None

    def update(self, positions: list[Position | None], timestamp: float):
        if not isfinite(timestamp) or (
            self.last_update is not None and timestamp <= self.last_update
        ):
            raise ValueError("Capture timestamps must be finite and strictly increasing.")
        if len(positions) != 2:
            raise ValueError("Provide exactly two positions: left and right, or None.")
        # Validate the entire frame before changing either slot.
        for position in positions:
            if position is not None and (
                len(position) != 2 or not all(isfinite(v) and 0 <= v <= 1 for v in position)
            ):
                raise ValueError("Positions must be finite normalized (x, y) pairs.")

        updated = []
        for previous, position in zip(self.hands, positions):
            if position is not None:
                velocity = (0.0, 0.0)
                if (previous.state == "TRACKED" and previous.last_seen is not None
                        and timestamp < previous.last_seen + LOSS_TIMEOUT):
                    elapsed = timestamp - previous.last_seen
                    velocity = tuple((current - old) / elapsed
                                     for current, old in zip(position, previous.position))
                hand = HandState(previous.slot, tuple(position), velocity,
                                 timestamp, "TRACKED", 1.0)
            elif (previous.last_seen is not None
                  and timestamp < previous.last_seen + LOSS_TIMEOUT):
                age = timestamp - previous.last_seen
                hand = replace(previous, state="COASTING", velocity=(0.0, 0.0),
                               confidence=max(0.0, 1.0 - age / LOSS_TIMEOUT))
            else:
                hand = replace(previous, state="LOST", velocity=(0.0, 0.0), confidence=0.0)
            updated.append(hand)

        self.hands = tuple(updated)
        self.last_update = timestamp
        return self.hands
