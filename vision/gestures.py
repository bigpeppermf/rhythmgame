"""Hybrid hand-shape recognition and brief, per-hand temporal stabilization."""

from dataclasses import dataclass
from math import acos, degrees, dist, isfinite


GESTURE_LABELS = {"Open_Palm": "OPEN_PALM", "Closed_Fist": "FIST", "Thumb_Up": "THUMBS_UP"}
VALID_GESTURES = ("UNKNOWN", "OPEN_PALM", "FIST", "THUMBS_UP", "PINCH")
MODEL_THRESHOLDS = {"OPEN_PALM": 0.55, "THUMBS_UP": 0.55, "FIST": 0.7}
PINCH_ENTER = 0.30
PINCH_RELEASE = 0.45


@dataclass(frozen=True)
class Gesture:
    label: str = "UNKNOWN"
    confidence: float = 0.0


def _points(landmarks, dimensions=3, aspect=1.0):
    if len(landmarks) != 21:
        return ()
    points = [((p.x * aspect, p.y) if dimensions == 2 else (p.x, p.y, p.z))
              for p in landmarks]
    return points if all(isfinite(v) for p in points for v in p) else ()


def _angle(a, b, c):
    first, second = [x - y for x, y in zip(a, b)], [x - y for x, y in zip(c, b)]
    length = dist(a, b) * dist(c, b)
    if length < 1e-10:
        return 0.0
    cosine = sum(x * y for x, y in zip(first, second)) / length
    return degrees(acos(max(-1.0, min(1.0, cosine))))


def _finger_extension(points, base):
    chain = sum(dist(points[i], points[i + 1]) for i in range(base, base + 3))
    if chain < 1e-6:
        return 0.0
    return dist(points[base], points[base + 3]) / chain


def _extended(points, base):
    return (_finger_extension(points, base) >= 0.78
            and _angle(points[base], points[base + 1], points[base + 2]) >= 140
            and dist(points[0], points[base + 3]) > dist(points[0], points[base + 1]) * 1.05)


def _curled(points, base, scale):
    """Positive curl evidence: bent joints and tip returning toward the wrist."""
    chain = sum(dist(points[i], points[i + 1]) for i in range(base, base + 3))
    return (chain >= 0.20 * scale
            and _finger_extension(points, base) <= 0.70
            and _angle(points[base], points[base + 1], points[base + 2]) <= 140
            and dist(points[0], points[base + 3]) <= dist(points[0], points[base + 1]) * 1.05)


def measure_hand(world_landmarks=(), image_landmarks=(), aspect=1.0):
    image = _points(image_landmarks, dimensions=2, aspect=aspect)
    world = _points(world_landmarks)
    shape = world or image
    if not shape:
        return None
    scale = max(dist(shape[5], shape[17]), dist(shape[0], shape[9]) * 0.8)
    if scale < 1e-6:
        return None
    ratios = [_finger_extension(shape, base) for base in (5, 9, 13, 17)]
    extended = [_extended(shape, base) or (bool(image) and _extended(image, base))
                for base in (5, 9, 13, 17)]
    curled = [not extended[index] and _curled(shape, base, scale)
              for index, base in enumerate((5, 9, 13, 17))]
    # Use image geometry for contact: monocular inferred z is particularly noisy
    # where the fingertips meet. Aspect correction makes distances pixel-isotropic.
    contact = image or shape
    contact_scale = max(dist(contact[5], contact[17]), dist(contact[0], contact[9]) * 0.8)
    if contact_scale < 1e-6:
        return None
    gap = dist(contact[4], contact[8]) / contact_scale
    world_gap = dist(world[4], world[8]) / scale if world else None
    index_reach = dist(shape[5], shape[8]) / scale
    # Closed-hand pinch: middle/ring/little must be positively curled. Index
    # reaches toward the thumb rather than being fully tucked into a fist.
    pinch_shape = all(curled[1:]) and index_reach >= 0.35 and ratios[0] >= 0.45
    if image and world_gap is not None and world_gap > 1.0:
        pinch_shape = False  # Clearly separated in depth, despite 2D overlap.
    thumb_up = False
    if image:
        thumb_up = (
            _angle(shape[2], shape[3], shape[4]) >= 145
            and image[2][1] - image[4][1] >= 0.45 * contact_scale
            and image[5][1] - image[4][1] >= 0.20 * contact_scale
            and sum(ratio < 0.70 for ratio in ratios) >= 3
            and sum(extended) <= 1
        )
    return {"gap": gap, "world_gap": world_gap, "extended": extended,
            "curled": curled, "index_reach": index_reach,
            "ratios": ratios, "pinch_shape": pinch_shape, "thumb_up": thumb_up}


def _pinch(features):
    if features is None or not features["pinch_shape"]:
        return Gesture()
    gap = features["gap"]
    if gap <= PINCH_ENTER:
        return Gesture("PINCH", 0.65 + 0.3 * (1 - gap / PINCH_ENTER))
    if gap <= PINCH_RELEASE:
        # Weak evidence only retains an already-confirmed pinch; cannot activate.
        return Gesture("PINCH", 0.45)
    return Gesture()


def pinch_gesture(world_landmarks=(), image_landmarks=(), aspect=1.0):
    return _pinch(measure_hand(world_landmarks, image_landmarks, aspect))


def analyze_gesture(categories, world_landmarks=(), image_landmarks=(), aspect=1.0):
    features = measure_hand(world_landmarks, image_landmarks, aspect)
    valid = [c for c in categories if isfinite(c.score) and 0 <= c.score <= 1]
    best = max(valid, key=lambda c: c.score) if valid else None
    recognized = Gesture()
    if best is not None:
        name = GESTURE_LABELS.get(best.category_name)
        if name and best.score >= MODEL_THRESHOLDS[name]:
            recognized = Gesture(name, float(best.score))
    pinch = _pinch(features)
    # The requested closed-hand pinch may get a canned Closed_Fist label. Let
    # the more specific all-finger geometry distinguish it from an ordinary fist.
    if pinch.label == "PINCH" and not features["thumb_up"]:
        gesture = pinch
    elif recognized.label == "FIST":
        gesture = recognized
    elif features is not None and features["thumb_up"]:
        gesture = Gesture("THUMBS_UP", max(0.8, recognized.confidence if recognized.label == "THUMBS_UP" else 0))
    elif features is not None and all(features["extended"]):
        gesture = Gesture("OPEN_PALM", max(0.8, recognized.confidence if recognized.label == "OPEN_PALM" else 0))
    else:
        gesture = recognized
    details = f"model={best.category_name}:{best.score:.2f}" if best else "model=none"
    if features is not None:
        world_text = f"{features['world_gap']:.2f}" if features["world_gap"] is not None else "n/a"
        details += f" gap={features['gap']:.2f} gap3d={world_text} extended={sum(features['extended'])}"
        details += f" curled={sum(features['curled'][1:])}/3 index_reach={features['index_reach']:.2f}"
    return gesture, details


def classify_gesture(categories, world_landmarks=(), image_landmarks=(), aspect=1.0):
    return analyze_gesture(categories, world_landmarks, image_landmarks, aspect)[0]


class GestureDebouncer:
    """Confirm in 40 ms; bridge short score dips only while a hand is present.

    Missing hands clear immediately. Unknown classifications can retain a stable
    pose for at most 100 ms with decaying confidence, not indefinitely.
    """

    def __init__(self):
        self.last_update = None
        self._reset()

    def _reset(self):
        self.stable = [Gesture(), Gesture()]
        self.supported_at = [float("-inf"), float("-inf")]
        self.pending = ["UNKNOWN", "UNKNOWN"]
        self.since = [0.0, 0.0]
        self.candidate_at = [float("-inf"), float("-inf")]

    def update(self, gestures, timestamp, present=None):
        if present is None:
            present = [g.label != "UNKNOWN" for g in gestures]
        if self.last_update is not None and timestamp - self.last_update >= 0.2:
            self._reset()
        self.last_update = timestamp
        output = []
        for slot, (gesture, detected) in enumerate(zip(gestures, present)):
            if not detected:
                self.stable[slot] = Gesture()
                self.pending[slot] = "UNKNOWN"
                self.supported_at[slot] = self.candidate_at[slot] = float("-inf")
                output.append(Gesture())
                continue
            supported = gesture.label != "UNKNOWN" and (
                gesture.confidence >= 0.55 or gesture.label == self.stable[slot].label)
            if supported:
                if gesture.label != self.pending[slot] or timestamp - self.candidate_at[slot] > 0.08:
                    self.pending[slot] = gesture.label
                    self.since[slot] = timestamp
                self.candidate_at[slot] = timestamp
                if gesture.label == self.stable[slot].label or timestamp >= self.since[slot] + 0.04:
                    self.stable[slot] = gesture
                    self.supported_at[slot] = timestamp
            age = timestamp - self.supported_at[slot]
            if age >= 0.1:
                self.stable[slot] = Gesture()
                output.append(Gesture())
            elif age > 0:
                output.append(Gesture(self.stable[slot].label, self.stable[slot].confidence * (1 - age / 0.1)))
            else:
                output.append(self.stable[slot])
        return output
