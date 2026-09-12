#!/usr/bin/env python3
"""Send packets built by the REAL vision encoder, so the game is tested against
what the tracker actually emits rather than against a hand-written stand-in.

    python3 tools/vision_bridge_check.py [--seconds 6]
"""
import argparse, sys, time
from dataclasses import dataclass
from math import sin, tau

sys.path.insert(0, "vision")
from udp_protocol import DEFAULT_HOST, DEFAULT_PORT, UdpHandSender  # noqa: E402


@dataclass
class Hand:
    slot: int
    position: tuple
    velocity: tuple
    confidence: float
    state: str


LANE = (0.29, 0.71)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default=DEFAULT_HOST)
    ap.add_argument("--port", type=int, default=DEFAULT_PORT)
    ap.add_argument("--fps", type=float, default=60.0)
    ap.add_argument("--seconds", type=float, default=0.0, help="0 = run forever")
    ap.add_argument("--preview", action="store_true",
                    help="also stream a synthetic self-view on the preview port")
    args = ap.parse_args()

    preview = None
    if args.preview:
        import numpy as np, cv2
        from preview import PreviewSender
        preview = PreviewSender(args.host)
        print(f"-> preview on :{preview.destination[1]}")

    sender = UdpHandSender(args.host, args.port)
    print(f"-> {sender.destination[0]}:{sender.destination[1]} using vision/udp_protocol.py")
    period, t0 = 1.0 / args.fps, time.perf_counter()
    prev = [0.5, 0.5]
    try:
        while True:
            now = time.perf_counter()
            t = now - t0
            if args.seconds and t > args.seconds:
                break
            hands = []
            for s in (0, 1):
                # Counter-phase sweeps so both lanes are exercised at once.
                y = 0.5 + 0.34 * sin(tau * 0.45 * t + (0.0 if s == 0 else 3.14159))
                hands.append(Hand(s, (LANE[s], y), (0.0, (y - prev[s]) / period), 0.95, "TRACKED"))
                prev[s] = y
            # Hand data first, always. The preview gets whatever is left.
            sender.send(hands, now, args.fps)

            if preview is not None:
                img = np.zeros((240, 320, 3), dtype=np.uint8)
                img[:] = (28, 22, 20)
                cv2.putText(img, "SELF VIEW", (74, 40), cv2.FONT_HERSHEY_SIMPLEX,
                            0.7, (200, 200, 210), 2, cv2.LINE_AA)
                for s_i, colour in ((0, (255, 220, 90)), (1, (150, 120, 255))):
                    cy = int(hands[s_i].position[1] * 200) + 20
                    cx = 70 if s_i == 0 else 250
                    cv2.circle(img, (cx, cy), 18, colour, -1)
                cv2.putText(img, f"t={t:5.1f}", (120, 228), cv2.FONT_HERSHEY_SIMPLEX,
                            0.5, (140, 140, 150), 1, cv2.LINE_AA)
                preview.maybe_send(img, now)
            slack = period - (time.perf_counter() - now)
            if slack > 0:
                time.sleep(slack)
    except KeyboardInterrupt:
        pass
    print(f"sent {sender.seq} hand packets, {sender.dropped} dropped")
    if preview is not None:
        print(f"sent {preview.sent} preview frames, {preview.dropped} dropped, "
              f"{preview.encode_ms:.2f} ms/encode")


if __name__ == "__main__":
    main()
