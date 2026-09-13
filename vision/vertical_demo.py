"""Step 1: two bare palms -> independent, uncalibrated positions.

Tracks observation age and velocity and sends both slots as JSON over UDP.
Your anatomical left palm controls the left cursor; your right controls the right.
"""

import argparse
from dataclasses import replace
import sys
from time import perf_counter

import cv2
import numpy as np


from hand_detector import DEFAULT_MODEL, DEFAULT_GESTURE_MODEL, PALM_LANDMARKS, HandDetector
from gestures import Gesture
from hand_state import HandStateTracker
from udp_protocol import DEFAULT_HOST, DEFAULT_PORT, UdpHandSender, port_number
from capture import CapturedFrame, LatestFrameCapture
from preview import PreviewSender, DEFAULT_PORT as PREVIEW_PORT


SLOTS = (("Left palm", (255, 255, 0)), ("Right palm", (0, 0, 255)))


def label(canvas, text, xy, color=(220, 220, 220)):
    cv2.putText(canvas, text, xy, cv2.FONT_HERSHEY_SIMPLEX, 0.55, color, 1, cv2.LINE_AA)


def draw_panel(states, fps, detection_ms, capture_fps=None, skipped=0, frame_age_ms=0.0,
               gestures_enabled=False, player_status=""):
    """Draw only synthetic cursors; the webcam image is absent."""
    panel = np.full((480, 640, 3), 22, dtype=np.uint8)
    label(panel, "Vertical input demo - y=0 top, y=1 bottom", (20, 28))
    label(panel, f"Loop: {fps:.1f} FPS | Detection: {detection_ms:.1f} ms", (20, 55))
    if capture_fps is not None:
        label(panel, f"Capture: {capture_fps:.1f} FPS | Skipped: {skipped} | Wait: {frame_age_ms:.1f} ms",
              (20, 76))
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
        if gestures_enabled:
            label(panel, f"{hand.gesture.label} {hand.gesture.confidence:.2f}",
                  (column - 100, 449), color)
    label(panel, player_status, (10, 105), (100, 220, 255))
    label(panel, "C: reset hands | D: debug | R: retry | Q/Esc: quit", (20, 465))
    return panel


def poll_keys(debug, reset=None, retry=None):
    """Keep window events responsive both during detection and capture waits."""
    key = cv2.waitKey(1) & 0xFF
    if key in (ord("q"), 27) or cv2.getWindowProperty("Vertical input", cv2.WND_PROP_VISIBLE) < 1:
        return debug, True
    if key == ord("d"):
        debug = not debug
        if not debug:
            try:
                cv2.destroyWindow("Debug camera")
            except cv2.error:
                pass  # D may be pressed before the first debug frame exists.
    if key == ord("c") and reset is not None:
        reset()
        debug = True
    if key == ord("r") and retry is not None:
        retry()
    return debug, False


def open_camera(requested, backend):
    """Open the requested index, or the first one that actually delivers a frame.

    Index 0 is not reliably a camera. Virtual devices (Iriun, OBS, DroidCam)
    register there and open successfully - or fail to - with nothing behind
    them, and the integrated camera lands at 1. isOpened() is not enough to
    tell: a device can open and never produce a frame. So the test is a read.
    """
    candidates = [requested] + [i for i in range(6) if i != requested]
    for index in candidates:
        cap = cv2.VideoCapture(index, backend)
        if cap.isOpened():
            ok, frame = cap.read()
            if ok and frame is not None:
                if index != requested:
                    print(f"Camera {requested} gave no frames; using camera {index} instead "
                          f"(pass --camera {index} to skip this probe).")
                return cap
        cap.release()
    return cv2.VideoCapture(requested, backend)  # let the caller's error path report it


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--camera", type=int, default=0)
    parser.add_argument("--video", help="Read a recorded clip instead of a webcam")
    parser.add_argument("--debug", action="store_true", help="Show camera and palm landmarks")
    parser.add_argument("--model", help="Override model path (must match selected task)")
    parser.add_argument("--gestures", action="store_true",
                        help="Recognize open palm, fist, thumbs-up, pinch; include gesture fields in UDP")
    parser.add_argument("--gesture-debug", action="store_true",
                        help="Enable gestures and print model scores, pinch gaps, and final labels at 4 Hz")
    parser.add_argument("--host", default=DEFAULT_HOST, help="UDP destination IPv4 address/hostname")
    parser.add_argument("--port", type=port_number, default=DEFAULT_PORT, help="UDP destination port")
    parser.add_argument("--no-udp", action="store_true", help="Run only the local cursor demo")
    parser.add_argument("--preview", action="store_true",
                        help="Stream the mirrored camera image to the game as a self-view")
    parser.add_argument("--preview-port", type=port_number, default=PREVIEW_PORT)
    args = parser.parse_args()
    args.gestures = args.gestures or args.gesture_debug
    # The brief's V4L2 backend is Linux-only. Choose a platform-specific backend.
    backend = cv2.CAP_DSHOW if sys.platform == "win32" else (
        cv2.CAP_V4L2 if sys.platform.startswith("linux") else cv2.CAP_ANY)
    model_path = args.model or (DEFAULT_GESTURE_MODEL if args.gestures else DEFAULT_MODEL)
    detector = HandDetector(model_path, gestures=args.gestures)
    state_tracker = HandStateTracker()
    def reset_hands():
        nonlocal state_tracker
        detector.reset_slots()
        state_tracker = HandStateTracker()
        print("Hand history cleared; confirming left/right hands again.", flush=True)

    def player_status():
        return detector.health_message or "Hand-only: strict left/right | no calibration needed"

    cap = cv2.VideoCapture(args.video) if args.video else open_camera(args.camera, backend)
    sender = None
    preview = None
    capture = None
    try:
        if not args.no_udp:
            sender = UdpHandSender(args.host, args.port, include_gestures=args.gestures)
            print(f"Sending hand JSON to {sender.destination[0]}:{sender.destination[1]}")
        if args.preview:
            preview = PreviewSender(args.host, args.preview_port)
            print(f"Streaming self-view to {preview.destination[0]}:{preview.destination[1]}")
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
            capture = LatestFrameCapture(cap)
        debug = args.debug
        print(player_status(), flush=True)
        count, fps, start = 0, 0.0, perf_counter()
        last_frame_at = start
        last_sequence, skipped = 0, 0
        last_udp_warning = float("-inf")
        last_gesture_log = float("-inf")
        cv2.imshow("Vertical input", draw_panel(state_tracker.hands, 0, 0,
                                               gestures_enabled=args.gestures, player_status=player_status()))
        while True:
            if capture is None:
                # Files intentionally remain sequential, with no discarded frames.
                ok, frame = cap.read()
                t_capture = perf_counter()
                if not ok:
                    break
                sample = CapturedFrame(last_sequence + 1, frame, t_capture, 0.0)
            else:
                sample = capture.get_latest(last_sequence)
                if sample is None:
                    now = perf_counter()
                    if now - last_frame_at >= 0.2:
                        # Display-only expiry: do not invent capture timestamps or
                        # send repeated stale frames. The UDP receiver times out.
                        unavailable = tuple(replace(hand, state="LOST", confidence=0.0,
                                                    velocity=(0.0, 0.0), gesture=Gesture())
                                            for hand in state_tracker.hands)
                        panel = draw_panel(unavailable, 0, 0, gestures_enabled=args.gestures,
                                           player_status=player_status())
                        label(panel, "Waiting for camera frame...", (20, 76))
                        cv2.imshow("Vertical input", panel)
                        if debug:
                            blank = np.zeros((480, 640, 3), dtype=np.uint8)
                            label(blank, "Waiting for camera frame...", (20, 40))
                            cv2.imshow("Debug camera", blank)
                    debug, quit_requested = poll_keys(debug, reset_hands, detector.retry)
                    if quit_requested:
                        break
                    if now - last_frame_at >= 2.0:
                        raise RuntimeError("No new camera frame for 2 seconds. Restart or reconnect the camera.")
                    continue
            skipped += max(0, sample.sequence - last_sequence - 1)
            last_sequence, last_frame_at = sample.sequence, sample.t_capture
            t_capture = sample.t_capture
            frame_age_ms = (perf_counter() - t_capture) * 1000
            frame = cv2.flip(sample.image, 1)  # Mirror so horizontal movement feels natural.
            before = perf_counter()
            hands = detector.detect(frame, t_capture)
            if args.gesture_debug and t_capture - last_gesture_log >= 0.25:
                for slot, ((name, _), hand) in enumerate(zip(SLOTS, hands)):
                    details = (f"{hand.gesture_debug} final={hand.gesture.label}:{hand.gesture.confidence:.2f}"
                               if hand is not None else "hand missing")
                    details += " " + detector.slots.diagnostics(slot)
                    candidates = ";".join(f"{p.handedness}:{p.score:.2f}@{p.position[0]:.2f},{p.position[1]:.2f}"
                                          for p in detector.candidates)
                    details += f" candidates=[{candidates}]"
                    print(f"{name}: {details}", flush=True)
                last_gesture_log = t_capture
            positions = [hand.position if hand is not None else None for hand in hands]
            states = state_tracker.update(positions, t_capture,
                                          [hand.gesture if hand is not None else Gesture() for hand in hands])
            detection_ms = (perf_counter() - before) * 1000
            # After the hand packet, never before: the preview has no latency
            # budget and must not delay the signal that does. It is throttled
            # internally and fails silently if nobody is listening.
            if preview is not None:
                preview.maybe_send(frame)

            count += 1
            if t_capture - start >= 1:
                fps = count / (t_capture - start)
                count, start = 0, t_capture
            if sender is not None and not sender.send(states, t_capture, fps):
                if t_capture - last_udp_warning >= 1.0:
                    print(f"UDP dropped {sender.dropped} packet(s): {sender.last_error}", file=sys.stderr)
                    last_udp_warning = t_capture
            cv2.imshow("Vertical input", draw_panel(
                states, fps, detection_ms, sample.fps if capture is not None else None,
                skipped, frame_age_ms, gestures_enabled=args.gestures, player_status=player_status()))
            if debug:
                height, width = frame.shape[:2]
                label(frame, player_status(), (10, 25), (100, 220, 255))
                for index, candidate in enumerate(detector.candidates):
                    label(frame, f"Hand {index + 1}: {candidate.handedness} {candidate.score:.2f}",
                          (10, 48 + 22 * index), (180, 180, 180))
                for (name, color), hand in zip(SLOTS, hands):
                    if hand is None:
                        continue
                    height, width = frame.shape[:2]
                    for index in PALM_LANDMARKS:
                        x, y = hand.landmarks[index]
                        cv2.circle(frame, (round(x * (width - 1)), round(y * (height - 1))),
                                   4, color, -1)
                    if args.gestures:
                        tips = [(round(hand.landmarks[i][0] * (width - 1)),
                                 round(hand.landmarks[i][1] * (height - 1))) for i in (4, 8, 12, 16, 20)]
                        cv2.line(frame, tips[0], tips[1], (180, 180, 180), 1)
                        for index, tip in enumerate(tips):
                            cv2.circle(frame, tip, 6, (0, 255, 0) if index < 2 else (0, 180, 255), 2)
                    point = (round(hand.position[0] * (width - 1)),
                             round(hand.position[1] * (height - 1)))
                    cv2.circle(frame, point, 12, color, 2)
                    caption = f"{name}: {hand.gesture.label}" if args.gestures else name
                    label(frame, caption, point, color)
                cv2.imshow("Debug camera", frame)
            debug, quit_requested = poll_keys(debug, reset_hands, detector.retry)
            if quit_requested:
                break
    finally:
        if preview is not None:
            print(f"Preview: {preview.sent} frames sent, {preview.dropped} dropped, "
                  f"{preview.encode_ms:.2f} ms/encode")
            preview.close()
        if sender is not None:
            sender.close()
        if capture is None:
            cap.release()
        elif not capture.close():
            print("Camera driver is still blocked in read(); capture worker will release it when it returns.",
                  file=sys.stderr)
        try:
            detector.close()
        finally:
            cv2.destroyAllWindows()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
    except (RuntimeError, ValueError, OSError, cv2.error) as error:
        print(f"Input demo failed: {error}", file=sys.stderr)
        sys.exit(1)
