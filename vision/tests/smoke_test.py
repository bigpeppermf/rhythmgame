"""Smoke test for the finished vision/ pieces. No camera required.

    python3 -m vision.tests.smoke_test

Covers the modules the README marks "Done" - filters.OneEuro, hands.HandReport,
emitter.Emitter, checked against the real wire format in PROTOCOL.md - plus a
check that the two intentionally-unimplemented pieces (slots.assign,
ColorTracker.detect) still raise NotImplementedError rather than silently
doing something else. It does not attempt to test tracking quality: there is
no tracker to test yet.
"""
import json
import socket
import sys

from ..emitter import Emitter, PROTOCOL_VERSION
from ..filters import OneEuro, OneEuro2D
from ..hands import COAST_SECONDS, COASTING, HandReport, LOST, TRACKED
from ..slots import assign
from ..trackers.color import ColorTracker

failures = 0


def check(ok: bool, label: str) -> None:
    global failures
    print(f"  {'PASS' if ok else 'FAIL'}  {label}")
    if not ok:
        failures += 1


def run_filters() -> None:
    f = OneEuro(min_cutoff=1.0, beta=0.007)
    check(f(0.5, 0.0) == 0.5, "OneEuro: first sample passes through untouched")
    check(f(0.5, 1 / 60) == 0.5, "OneEuro: unmoving signal stays put")

    f2 = OneEuro(min_cutoff=1.0, beta=0.007)
    t, x, y = 0.0, 0.0, 0.0
    for _ in range(60):
        t += 1 / 60
        x += 0.1
        y = f2(x, t)
    check(abs(y - x) < x, "OneEuro: tracks a ramp (lags behind, doesn't ignore it)")
    check(f2.velocity() > 0, "OneEuro: velocity is positive during a rising ramp")

    f2d = OneEuro2D(min_cutoff=1.0, beta=0.007)
    check(f2d((0.5, 0.5), 0.0) == (0.5, 0.5),
          "OneEuro2D: first sample passes through on both axes")
    f2d.reset()
    check(f2d.x._x is None and f2d.y._x is None, "OneEuro2D.reset() clears both axes")


def run_hands() -> None:
    h = HandReport(0)
    check(h.state == LOST, "HandReport starts LOST")

    h.update(0.3, 0.4, 1.0, 0.0, 0.9, now=10.0)
    check(h.state == TRACKED and h.conf == 0.9, "update() -> TRACKED with given confidence")

    h.coast(now=10.0 + COAST_SECONDS / 2)
    check(h.state == COASTING, "coast() before timeout -> COASTING")
    check(0.0 < h.conf < 0.9, "coast() decays confidence, doesn't zero it early")

    h.coast(now=10.0 + COAST_SECONDS + 0.01)
    check(h.state == LOST and h.conf == 0.0, "coast() past COAST_SECONDS -> LOST, conf 0")
    check(h.vx == 0.0 and h.vy == 0.0, "LOST clears velocity too")

    d = h.to_dict()
    check(set(d.keys()) == {"slot", "x", "y", "vx", "vy", "conf", "state"},
          "to_dict() has exactly the PROTOCOL.md per-hand fields")


def run_emitter() -> None:
    listener = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    listener.bind(("127.0.0.1", 9091))
    listener.settimeout(1.0)

    em = Emitter(host="127.0.0.1", port=9091)
    h0 = HandReport(0)
    h0.update(0.3, 0.4, 1.0, 0.0, 0.9, now=1.0)
    h1 = HandReport(1)  # never updated - stays LOST, and must still be sent.
    em.send([h0, h1], t_capture=1.234, fps=59.9)

    try:
        raw, _ = listener.recvfrom(4096)
        payload = json.loads(raw.decode())
        check(payload["v"] == PROTOCOL_VERSION, "emitter: v matches PROTOCOL_VERSION")
        check(payload["seq"] == 1, "emitter: seq starts at 1")
        check(abs(payload["t_capture"] - 1.234) < 1e-6, "emitter: t_capture passed through")
        check(len(payload["hands"]) == 2, "emitter: always exactly 2 hands")
        check(payload["hands"][1]["state"] == LOST,
              "emitter: an unseen hand still goes out, as LOST not omitted")
        check(len(raw) < 512, f"emitter: packet under 512 bytes target, got {len(raw)}")
    except socket.timeout:
        check(False, "emitter: packet arrived over real UDP")
    finally:
        listener.close()

    try:
        em.send([h0], t_capture=1.0, fps=60.0)
        check(False, "emitter: rejects a hands list that isn't exactly length 2")
    except AssertionError:
        check(True, "emitter: rejects a hands list that isn't exactly length 2")
    finally:
        em.close()


def run_stubs() -> None:
    """These two are your work, not a bug - see vision/README.md. Confirm they
    fail loudly instead of silently returning nonsense."""
    try:
        assign([], [None, None], 1 / 60)
        check(False, "slots.assign() raises NotImplementedError (unimplemented on purpose)")
    except NotImplementedError:
        check(True, "slots.assign() raises NotImplementedError (unimplemented on purpose)")

    try:
        ColorTracker().detect(None)
        check(False,
              "ColorTracker.detect() raises NotImplementedError (unimplemented on purpose)")
    except NotImplementedError:
        check(True,
              "ColorTracker.detect() raises NotImplementedError (unimplemented on purpose)")


def main() -> None:
    run_filters()
    run_hands()
    run_emitter()
    run_stubs()
    print(f"\n{'ALL PASS' if failures == 0 else 'FAILURES'} ({failures} failure{'' if failures == 1 else 's'})")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
