"""Step 1: two bare palms -> independent, uncalibrated positions.

Tracks observation age and velocity and sends both slots as JSON over UDP.
Your anatomical left palm controls the left cursor; your right controls the right.
"""

import argparse
import sys
from time import perf_counter

import cv2
import numpy as np


from hand_detector import DEFAULT_MODEL, PALM_LANDMARKS, HandDetector
from hand_state import HandStateTracker
from udp_protocol import DEFAULT_HOST, DEFAULT_PORT, UdpHandSender, port_number


SLOTS = (("Left palm", (255, 255, 0)), ("Right palm", (0, 0, 255)))


def label(canvas, text, xy, color=(220, 220, 220)):
    cv2.putText(canvas, text, xy, cv2.FONT_HERSHEY_SIMPLEX, 0.55, color, 1, cv2.LINE_AA)


def draw_panel(states, fps, detection_ms):
    """Draw only synthetic cursors; the webcam image is absent."""
    panel = np.full((480, 640, 3), 22, dtype=np.uint8)
    label(panel, "Vertical input demo - y=0 top, y=1 bottom", (20, 28))
    label(panel, f"Loop: {fps:.1f} FPS | Detection: {detection_ms:.1f} ms", (20, 55))
    for slot, ((name, color), hand) in enumerate(zip(SLOTS, states)):
        column = 160 + slot * 320
        cv2.line(panel, (column, 110), (column, 350), (90, 90, 90), 3)
        label(panel, name, (column - 100, 90), color)
        display_color = tuple(round(22 + (v - 22) * hand.confidence) for v in color)
        if hand.state != "LOST":
            x, y = hand.position
            cv2.circle(panel, (column, round(110 + y * 240)), 17, display_color, -1)
            label(panel, f"x={x:.2f} y={y:.2f}", (column - 100, 402))
        label(panel, f"{hand.state} conf={hand.confidence:.2f}", (column - 120, 377))
        vx, vy = hand.velocity
        label(panel, f"vx={vx:.2f} vy={vy:.2f}", (column - 100, 427))
    label(panel, "D: toggle palm debug | Q or Esc: quit", (20, 465))
    return panel


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--camera", type=int, default=0)
    parser.add_argument("--video", help="Read a recorded clip instead of a webcam")
    parser.add_argument("--debug", action="store_true", help="Show camera and palm landmarks")
    parser.add_argument("--model", default=str(DEFAULT_MODEL), help="Path to Hand Landmarker model")
    parser.add_argument("--host", default=DEFAULT_HOST, help="UDP destination IPv4 address/hostname")
    parser.add_argument("--port", type=port_number, default=DEFAULT_PORT, help="UDP destination port")
    parser.add_argument("--no-udp", action="store_true", help="Run only the local cursor demo")
    args = parser.parse_args()
    # The brief's V4L2 backend is Linux-only. Choose a platform-specific backend.
    backend = cv2.CAP_DSHOW if sys.platform == "win32" else (
        cv2.CAP_V4L2 if sys.platform.startswith("linux") else cv2.CAP_ANY)
    detector = HandDetector(args.model)
    state_tracker = HandStateTracker()
    cap = cv2.VideoCapture(args.video) if args.video else cv2.VideoCapture(args.camera, backend)
    sender = None
    try:
        if not args.no_udp:
            sender = UdpHandSender(args.host, args.port)
            print(f"Sending hand JSON to {sender.destination[0]}:{sender.destination[1]}")
        if not cap.isOpened():
            raise RuntimeError("Cannot open input. Close other camera apps or try --camera 1.")
        if not args.video:
            for prop, value in (
                (cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*"MJPG")),
                (cv2.CAP_PROP_FRAME_WIDTH, 640), (cv2.CAP_PROP_FRAME_HEIGHT, 480),
                (cv2.CAP_PROP_FPS, 60), (cv2.CAP_PROP_BUFFERSIZE, 1),
            ):
                accepted = cap.set(prop, value)
                print(f"Camera property {prop}: requested={value}, readback={cap.get(prop)}, accepted={accepted}")
        debug = args.debug
        count, fps, start = 0, 0.0, perf_counter()
        last_udp_warning = float("-inf")
        while True:
            ok, frame = cap.read()
            t_capture = perf_counter()  # Read-completion time, not sensor exposure time.
            if not ok:
                if args.video:
                    break
                raise RuntimeError("Camera stopped delivering frames.")
            frame = cv2.flip(frame, 1)  # Mirror so horizontal movement feels natural.
            before = perf_counter()
            hands = detector.detect(frame, t_capture)
            positions = [hand.position if hand is not None else None for hand in hands]
            states = state_tracker.update(positions, t_capture)
            detection_ms = (perf_counter() - before) * 1000
            count += 1
            if t_capture - start >= 1:
                fps = count / (t_capture - start)
                count, start = 0, t_capture
            if sender is not None and not sender.send(states, t_capture, fps):
                if t_capture - last_udp_warning >= 1.0:
                    print(f"UDP dropped {sender.dropped} packet(s): {sender.last_error}", file=sys.stderr)
                    last_udp_warning = t_capture
            cv2.imshow("Vertical input", draw_panel(states, fps, detection_ms))
            if debug:
                for (name, color), hand in zip(SLOTS, hands):
                    if hand is None:
                        continue
                    height, width = frame.shape[:2]
                    for index in PALM_LANDMARKS:
                        x, y = hand.landmarks[index]
                        cv2.circle(frame, (round(x * (width - 1)), round(y * (height - 1))),
                                   4, color, -1)
                    point = (round(hand.position[0] * (width - 1)),
                             round(hand.position[1] * (height - 1)))
                    cv2.circle(frame, point, 12, color, 2)
                    label(frame, name, point, color)
                cv2.imshow("Debug camera", frame)
            key = cv2.waitKey(1) & 0xFF
            if key in (ord("q"), 27) or cv2.getWindowProperty("Vertical input", cv2.WND_PROP_VISIBLE) < 1:
                break
            if key == ord("d"):
                debug = not debug
                if not debug:
                    cv2.destroyWindow("Debug camera")
    finally:
        if sender is not None:
            sender.close()
        cap.release()
        detector.close()
        cv2.destroyAllWindows()


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, ValueError, OSError, cv2.error) as error:
        print(f"Input demo failed: {error}", file=sys.stderr)
        sys.exit(1)
