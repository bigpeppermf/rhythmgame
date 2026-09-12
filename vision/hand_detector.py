"""MediaPipe palm observations with anatomical slot initialization and continuity."""

from dataclasses import dataclass, replace
from itertools import product
from math import dist, isfinite
from pathlib import Path

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
    """Seed from handedness, then match nearby palms one-to-one for 200 ms.

    Missing observations remain None; history is only used for association.
    Full overlap/occlusion can still make identity ambiguous.
    """

    def __init__(self):
        self.previous = [None, None]
        self.seen_at = [float("-inf"), float("-inf")]

    def update(self, palms, timestamp):
        costs = [{}, {}]
        for slot, name in enumerate(("Left", "Right")):
            age = timestamp - self.seen_at[slot]
            recent = self.previous[slot] is not None and 0 <= age <= 0.2
            for index, palm in enumerate(palms):
                if recent:
                    distance = dist(self.previous[slot], palm.position)
                    # Allow small landmark noise plus up to 2 image units/sec.
                    if distance <= 0.03 + 2.0 * age:
                        costs[slot][index] = distance
                elif palm.handedness == name and palm.score >= 0.65:
                    costs[slot][index] = 1 - palm.score
        best, best_key = (None, None), (1, float("inf"))
        for assignment in product([None, *costs[0]], [None, *costs[1]]):
            used = [index for index in assignment if index is not None]
            if len(set(used)) != len(used):
                continue
            key = (-len(used), sum(costs[slot][index] for slot, index in
                                  enumerate(assignment) if index is not None))
            if key < best_key:
                best, best_key = assignment, key
        observations = [None, None]
        for slot, index in enumerate(best):
            if index is not None:
                observations[slot] = palms[index]
                self.previous[slot] = palms[index].position
                self.seen_at[slot] = timestamp
        return observations


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
        self.landmarker = task_class.create_from_options(options)
        self.slots = PalmSlots()
        self.gesture_debouncer = GestureDebouncer()
        self.last_timestamp_ms = -1

    def detect(self, frame, timestamp):
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        image = self.mp.Image(image_format=self.mp.ImageFormat.SRGB, data=rgb)
        # Tasks requires strictly increasing integer milliseconds.
        timestamp_ms = max(self.last_timestamp_ms + 1, int(timestamp * 1000))
        self.last_timestamp_ms = timestamp_ms
        if self.gestures_enabled:
            result = self.landmarker.recognize_for_video(image, timestamp_ms)
        else:
            result = self.landmarker.detect_for_video(image, timestamp_ms)
        palms = self.slots.update(extract_palms(result, frame.shape[1] / frame.shape[0]), timestamp)
        if self.gestures_enabled:
            gestures = self.gesture_debouncer.update(
                [palm.gesture if palm is not None else Gesture() for palm in palms], timestamp,
                present=[palm is not None for palm in palms])
            palms = [replace(palm, gesture=gesture) if palm is not None else None
                     for palm, gesture in zip(palms, gestures)]
        return palms

    def close(self):
        self.landmarker.close()
