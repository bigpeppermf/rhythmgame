"""Vision module entry point.

    python3 -m vision.main --probe          # camera diagnostics, no tracking
    python3 -m vision.main --debug          # tracking + debug window
    python3 -m vision.main --no-emit        # run without sending packets

Pipeline, in order:

    capture -> tracker.detect -> slots.assign -> OneEuro -> HandReport -> emit

Each stage is replaceable without touching the others. That is the whole point:
swapping ColorTracker for a MediaPipe tracker changes one line here and nothing
anywhere else.
"""
import argparse
import time

from . import config
from .capture import Camera
from .emitter import Emitter
from .filters import OneEuro2D
from .hands import HandReport
from .slots import assign


def probe(cam):
    """Answer the first-two-hours checklist. Measurement, not features.

    CAP_PROP_FPS lies - it reports what the driver claims, not what you get.
    Only a timed loop tells the truth.
    """
    print("requested vs accepted:")
    for k, v in cam.settings().items():
        print(f"  {k:16} {v}")

    print("\nmeasuring actual throughput (5s)...")
    t0 = time.perf_counter()
    frames, last_seq = 0, -1
    gaps = []
    while time.perf_counter() - t0 < 5.0:
        seq, t_cap, frame = cam.read()
        if frame is not None and seq != last_seq:
            if last_seq >= 0:
                gaps.append(t_cap)
            last_seq = seq
            frames += 1
        time.sleep(0.001)

    elapsed = time.perf_counter() - t0
    print(f"  {frames} new frames in {elapsed:.1f}s  =  {frames/elapsed:.1f} fps")
    if len(gaps) > 2:
        deltas = [(b - a) * 1000 for a, b in zip(gaps, gaps[1:])]
        deltas.sort()
        mid = len(deltas) // 2
        print(f"  frame interval  median {deltas[mid]:.1f}ms"
              f"  p95 {deltas[int(len(deltas) * 0.95)]:.1f}ms"
              f"  max {deltas[-1]:.1f}ms")
        print("\n  p95 far above median means jitter, which is the number that")
        print("  actually matters - constant latency calibrates away, variance does not.")


def run(args):
    cam = Camera(**config.CAMERA)
    try:
        if args.probe:
            probe(cam)
            return

        # TODO(vision): swap in MediaPipe here once the color tracker works.
        from .trackers.color import ColorTracker
        tracker = ColorTracker()

        emitter = Emitter(**config.EMIT, enabled=not args.no_emit)
        reports = [HandReport(0), HandReport(1)]
        filters = [OneEuro2D(**config.FILTER), OneEuro2D(**config.FILTER)]
        prev = [None, None]
        last_seq, last_t = -1, time.perf_counter()
        fps = 0.0

        while True:
            seq, t_cap, frame = cam.read()
            if frame is None or seq == last_seq:
                time.sleep(0.001)
                continue
            dt = max(t_cap - last_t, 1e-4)
            fps = 0.9 * fps + 0.1 * (1.0 / dt)
            last_seq, last_t = seq, t_cap

            detections = tracker.detect(frame)
            matched = assign(detections, prev, dt)

            for slot in (0, 1):
                det = matched[slot]
                if det is None:
                    reports[slot].coast(t_cap)
                    if reports[slot].state == "LOST":
                        prev[slot] = None
                        filters[slot].reset()
                    continue
                x, y = filters[slot]((det[0], det[1]), t_cap)
                vx, vy = filters[slot].velocity()
                reports[slot].update(x, y, vx, vy, det[2], t_cap)
                prev[slot] = (x, y)

            emitter.send(reports, t_cap, fps)

            if args.debug:
                import cv2
                cv2.imshow("vision", tracker.debug_overlay(frame))
                if cv2.waitKey(1) & 0xFF == 27:
                    break
    finally:
        cam.close()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--probe", action="store_true",
                    help="camera diagnostics only, no tracking")
    ap.add_argument("--debug", action="store_true", help="show debug window")
    ap.add_argument("--no-emit", action="store_true", help="do not send packets")
    run(ap.parse_args())


if __name__ == "__main__":
    main()
