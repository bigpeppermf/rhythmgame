"""One Euro filter.

Naive smoothing trades latency for stability at a fixed rate, which is exactly
the wrong deal here: you need heavy smoothing when the hand is resting (to kill
sensor jitter) and almost none when it is moving fast (or you add lag to the
strike that matters).

One Euro adapts. Its cutoff frequency rises with observed speed, so it is
aggressive at rest and nearly transparent during fast motion. It was designed
for exactly this problem - noisy input from camera-based interaction.

Tuning, in order:
  1. Set beta = 0. Lower min_cutoff until resting jitter is gone.
  2. Raise beta until fast motion stops feeling laggy.
"""
import math


def _alpha(cutoff, dt):
    tau = 1.0 / (2.0 * math.pi * cutoff)
    return 1.0 / (1.0 + tau / dt)


class OneEuro:
    def __init__(self, min_cutoff=1.0, beta=0.007, d_cutoff=1.0):
        self.min_cutoff = min_cutoff
        self.beta = beta
        self.d_cutoff = d_cutoff
        self._x = None
        self._dx = 0.0
        self._t = None

    def __call__(self, x, t):
        if self._t is None:
            self._t, self._x = t, x
            return x
        dt = t - self._t
        if dt <= 0.0:
            return self._x
        self._t = t

        dx = (x - self._x) / dt
        self._dx += _alpha(self.d_cutoff, dt) * (dx - self._dx)

        # The adaptive part: faster motion raises the cutoff, letting more
        # signal through and less smoothing be applied.
        cutoff = self.min_cutoff + self.beta * abs(self._dx)
        self._x += _alpha(cutoff, dt) * (x - self._x)
        return self._x

    def velocity(self):
        """Smoothed derivative, in units per second. Goes into the packet so
        Godot can extrapolate between camera frames."""
        return self._dx

    def reset(self):
        self._x = None
        self._dx = 0.0
        self._t = None


class OneEuro2D:
    """Independent filters per axis, sharing tuning."""

    def __init__(self, **kw):
        self.x = OneEuro(**kw)
        self.y = OneEuro(**kw)

    def __call__(self, pt, t):
        return self.x(pt[0], t), self.y(pt[1], t)

    def velocity(self):
        return self.x.velocity(), self.y.velocity()

    def reset(self):
        self.x.reset()
        self.y.reset()
