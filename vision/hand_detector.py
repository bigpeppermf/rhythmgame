"""Hand-only observations with strict anatomical slots and confirmed reacquisition."""

from dataclasses import dataclass, replace
from math import dist, isfinite
from pathlib import Path
import sys

import cv2
from gestures import Gesture, GestureDebouncer, analyze_gesture

PALM_LANDMARKS = (0, 5, 9, 13, 17)
DEFAULT_MODEL = Path(__file__).parent / "models" / "hand_landmarker.task"
DEFAULT_GESTURE_MODEL = Path(__file__).parent / "models" / "gesture_recognizer.task"


@dataclass(frozen=True)
class Palm:
    position: tuple[float, float]
    handedness: str
    score: float  # Handedness certainty, NOT hand-presence confidence.
    landmarks: tuple[tuple[float, float], ...]
    gesture: Gesture = Gesture()
    gesture_debug: str = ""


def extract_palms(result, image_aspect=1.0):
    """Average palm landmarks and correct labels for the mirrored demo input."""
    palms = []
    gesture_results = getattr(result, "gestures", [])
    world_results = getattr(result, "hand_world_landmarks", [])
    for index, (landmarks, categories) in enumerate(zip(result.hand_landmarks, result.handedness)):
        if len(landmarks) != 21 or not categories:
            continue
        category = max(categories, key=lambda item: item.score)
        if category.category_name not in ("Left", "Right"):
            continue
        points = tuple((point.x, point.y) for point in landmarks)
        if not all(isfinite(value) for point in points for value in point):
            continue
        center = tuple(sum(points[i][axis] for i in PALM_LANDMARKS) / 5
                       for axis in (0, 1))
        if not all(0 <= value <= 1 for value in center):
            continue
        # The live demo showed opposite anatomical labels after its input flip.
        # Correct once here, before continuity tracking and state assignment.
        handedness = {"Left": "Right", "Right": "Left"}[category.category_name]
        world = world_results[index] if index < len(world_results) else ()
        gesture, details = (analyze_gesture(gesture_results[index], world, landmarks, image_aspect)
                            if index < len(gesture_results) else (Gesture(), ""))
        palms.append(Palm(center, handedness, category.score, points, gesture,
                          f"{details} raw={gesture.label}:{gesture.confidence:.2f}"))
    return palms


class PalmSlots:
    """Every observation must match the slot's anatomical label at >= 0.80.

    Continuity may reject a match, never override handedness. New/returning
    hands need 60 ms of consistent observations. This does not identify people.
    """
    MIN_HANDEDNESS = .80
    CONFIRM_SECONDS = .06

    def __init__(self):
        self.previous = [None, None]
        self.seen_at = [float("-inf"), float("-inf")]
        self.active = [False, False]
        self.pending = [None, None]
        self.pending_since = [0., 0.]
        self.pending_seen = [float("-inf"), float("-inf")]
        self.reasons = ["no_matching_hand"] * 2
        self.timestamp = None

    def update(self, palms, timestamp):
        if not isfinite(timestamp) or (self.timestamp is not None and timestamp <= self.timestamp):
            raise ValueError("Hand observations require increasing finite timestamps")
        self.timestamp = timestamp
        output = [None, None]
        # Snapshot history so processing the left slot cannot affect the right.
        recent = [self.previous[i] is not None and timestamp - self.seen_at[i] <= .2
                  for i in range(2)]
        for slot, name in enumerate(("Left", "Right")):
            labeled = [p for p in palms if p.handedness == name]
            candidates = [p for p in labeled if isfinite(p.score) and self.MIN_HANDEDNESS <= p.score <= 1
                          and all(isfinite(v) and 0 <= v <= 1 for v in p.position)]
            reason = "low_handedness" if labeled else "no_matching_hand"
            chosen = None
            if len(candidates) > 1:
                reason = "ambiguous_same_side"
            elif len(candidates) == 1:
                palm = candidates[0]
                own_gap = dist(palm.position, self.previous[slot]) if recent[slot] else float("inf")
                other = 1 - slot
                if recent[slot] and own_gap > .03 + 2 * (timestamp - self.seen_at[slot]):
                    reason = "motion"
                elif (recent[other]
                      and dist(palm.position, self.previous[other]) < own_gap
                      and dist(palm.position, self.previous[other]) <= .03 + 2 * (timestamp - self.seen_at[other])):
                    reason = "opposite_track_conflict"
                else:
                    chosen = palm
            if chosen is None:
                self.active[slot] = False
                self.pending[slot] = None
                self.reasons[slot] = reason
                continue
            gap_time = timestamp - self.pending_seen[slot]
            if (self.pending[slot] is None or gap_time > .15
                    or dist(chosen.position, self.pending[slot]) > .03 + 2 * gap_time):
                self.active[slot] = False
                self.pending_since[slot] = timestamp
            self.pending[slot] = chosen.position
            self.pending_seen[slot] = timestamp
            if self.active[slot] or timestamp - self.pending_since[slot] >= self.CONFIRM_SECONDS:
                output[slot] = chosen
                self.active[slot] = True
                self.reasons[slot] = "accepted"
            else:
                self.reasons[slot] = "confirming_handedness"
        for slot, palm in enumerate(output):
            if palm is not None:
                self.previous[slot] = palm.position
                self.seen_at[slot] = timestamp
        return output

    def diagnostics(self, slot):
        return f"slot_check={self.reasons[slot]}"


class HandDetector:
    """Accept mirrored BGR frames; extract_palms corrects left/right labels."""

    def __init__(self, model_path=None, gestures=False):
        if model_path is None:
            model_path = DEFAULT_GESTURE_MODEL if gestures else DEFAULT_MODEL
        try:
            import mediapipe as mp
        except ImportError as error:
            raise RuntimeError(
                "MediaPipe is missing. Install vision/requirements.txt with this Python."
            ) from error
        if not Path(model_path).is_file():
            command = "python vision/download_model.py" + (" --gestures" if gestures else "")
            raise RuntimeError(f"Model is missing. Run: {command}")
        self.mp = mp
        self.gestures_enabled = gestures
        options_class = (mp.tasks.vision.GestureRecognizerOptions if gestures
                         else mp.tasks.vision.HandLandmarkerOptions)
        options = options_class(
            base_options=mp.tasks.BaseOptions(model_asset_path=str(model_path)),
            running_mode=mp.tasks.vision.RunningMode.VIDEO,
            num_hands=2,
            min_hand_detection_confidence=0.5,
            min_hand_presence_confidence=0.5,
            min_tracking_confidence=0.5,
        )
        task_class = mp.tasks.vision.GestureRecognizer if gestures else mp.tasks.vision.HandLandmarker
        self._task_factory = lambda: task_class.create_from_options(options)
        self.landmarker = self._task_factory()
        self.recovery_failures = 0
        self.paused = False
        self.health_message = ""
        self.slots = PalmSlots()
        self.candidates = []
        self.gesture_debouncer = GestureDebouncer()
        self.last_timestamp_ms = -1

    def detect(self, frame, timestamp):
        if self.paused:
            return self._unavailable(frame, timestamp)
        if self.landmarker is None:
            try:
                self.landmarker = self._task_factory()
            except (RuntimeError, ValueError, OSError) as error:
                self.paused = True
                self.health_message = "Detector restart failed - R: retry | Q: quit"
                print(f"{self.health_message}: {error}", file=sys.stderr, flush=True)
                return self._unavailable(frame, timestamp)
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        image = self.mp.Image(image_format=self.mp.ImageFormat.SRGB, data=rgb)
        # Tasks requires strictly increasing integer milliseconds.
        timestamp_ms = max(self.last_timestamp_ms + 1, int(timestamp * 1000))
        self.last_timestamp_ms = timestamp_ms
        try:
            if self.gestures_enabled:
                result = self.landmarker.recognize_for_video(image, timestamp_ms)
            else:
                result = self.landmarker.detect_for_video(image, timestamp_ms)
        except RuntimeError as error:
            if not self.gestures_enabled or not self._ownership_error(error):
                raise
            self.recovery_failures += 1
            self._close_hand_task()
            self.paused = self.recovery_failures >= 3
            self.health_message = ("Detector paused after repeated errors - R: retry" if self.paused
                                   else "Recovering gesture detector - input unavailable")
            print(f"{self.health_message} ({self.recovery_failures}/3): {error}", file=sys.stderr, flush=True)
            # Return unavailable input before creating a replacement on the
            # next frame. Never reuse a gesture from the failed graph.
            return self._unavailable(frame, timestamp)
        if self.health_message:
            print("Gesture detector recovered.", flush=True)
        self.recovery_failures = 0
        self.health_message = ""
        aspect = frame.shape[1] / frame.shape[0]
        self.candidates = extract_palms(result, aspect)
        palms = self.slots.update(self.candidates, timestamp)
        if self.gestures_enabled:
            gestures = self.gesture_debouncer.update(
                [palm.gesture if palm is not None else Gesture() for palm in palms], timestamp,
                present=[palm is not None for palm in palms])
            palms = [replace(palm, gesture=gesture) if palm is not None else None
                     for palm, gesture in zip(palms, gestures)]
        return palms

    def reset_slots(self):
        self.slots = PalmSlots()
        self.gesture_debouncer = GestureDebouncer()

    @staticmethod
    def _ownership_error(error):
        return ("Packet isn't the sole owner of the holder" in str(error)
                and "ConcatenateTensorVectorCalculator" in str(error))

    def _unavailable(self, frame, timestamp):
        self.candidates = []
        self.gesture_debouncer = GestureDebouncer()
        self.slots.update([], timestamp)
        return [None, None]

    def retry(self):
        if self.paused:
            self.paused = False
            self.recovery_failures = 0
            self.health_message = "Retrying gesture detector - input unavailable"

    def _close_hand_task(self):
        task, self.landmarker = self.landmarker, None
        if task is not None:
            try:
                task.close()
            except RuntimeError as error:
                # A failed graph can report the same error again when closed.
                if not self._ownership_error(error):
                    raise

    def close(self):
        self._close_hand_task()
