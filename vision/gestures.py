"""Hybrid hand-shape recognition and brief, per-hand temporal stabilization."""

from dataclasses import dataclass
from math import acos, atan2, degrees, dist, isfinite


GESTURE_LABELS = {"Open_Palm": "OPEN_PALM", "Closed_Fist": "FIST", "Thumb_Up": "THUMBS_UP"}
VALID_GESTURES = ("UNKNOWN", "OPEN_PALM", "FIST", "THUMBS_UP", "PINCH")
MODEL_THRESHOLDS = {"OPEN_PALM": 0.55, "THUMBS_UP": 0.55, "FIST": 0.7}
SUPPORTED_FIST_THRESHOLD = 0.55
PINCH_ENTER = 0.30
PINCH_RELEASE = 0.45
PINCH_INDEX_REACH = 0.75
PINCH_PALM_CLEARANCE = 0.60
PINCH_THUMB_REACH = 0.55
PINCH_FINGER_CLEARANCE = 0.50
# Intended upright poses measured 0.8-21.2 degrees in live testing. Leave a
# small margin for landmark jitter; strict 5-degree gating rejected the pose.
THUMB_MAX_TILT = 25.0
THUMB_MIN_GAP = 0.55
OPEN_THUMB_INDEX_GAP = 0.55
OPEN_MIN_TIP_GAP = 0.18


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
    """Accept a loose curl without requiring the tip to reach the palm."""
    chain = sum(dist(points[i], points[i + 1]) for i in range(base, base + 3))
    # Keep positive bend evidence, but allow fingertips beyond the PIP joint.
    # A straight supporting finger must still fail, even when angled sideways.
    return (chain >= 0.20 * scale
            and _finger_extension(points, base) <= 0.85
            and _angle(points[base], points[base + 1], points[base + 2]) <= 140)


def _segment_distance(point, start, end):
    direction = [b - a for a, b in zip(start, end)]
    length_squared = sum(value * value for value in direction)
    if length_squared < 1e-12:
        return dist(point, start)
    fraction = sum((p - a) * d for p, a, d in zip(point, start, direction)) / length_squared
    fraction = max(0.0, min(1.0, fraction))
    return dist(point, [a + fraction * d for a, d in zip(start, direction)])


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
    # Require visible separation of every fingertip pair, including non-adjacent
    # fingers that cross. Image geometry prevents noisy inferred z from turning
    # visibly touching tips into a separated open hand.
    tips = (4, 8, 12, 16, 20)
    tip_gaps = [(dist(contact[a], contact[b]) / contact_scale, a, b)
                for i, a in enumerate(tips) for b in tips[i + 1:]]
    min_tip_gap, closest_a, closest_b = min(tip_gaps)
    world_gap = dist(world[4], world[8]) / scale if world else None
    index_reach = dist(shape[5], shape[8]) / scale
    thumb_reach = dist(shape[2], shape[4]) / scale
    # Diagnostic only: user recordings show overlapping approach angles for
    # fists and pinches, especially with uncertain fingertip depth estimates.
    index_direction = [b - a for a, b in zip(shape[7], shape[8])]
    thumb_direction = [b - a for a, b in zip(shape[3], shape[4])]
    approach_angle = _angle(index_direction, [0.0] * len(shape[0]), thumb_direction)
    # Measure BOTH tips against the palm bones and the remaining fingers, not
    # just each other. This rejects contact over a fist's raised index knuckle.
    palm_segments = ((0, 5), (0, 9), (0, 13), (0, 17), (5, 9), (9, 13), (13, 17))
    finger_segments = [(joint, joint + 1) for base in (9, 13, 17)
                       for joint in range(base, base + 3)]
    palm_clearance = min(_segment_distance(shape[tip], shape[a], shape[b])
                         for tip in (4, 8) for a, b in palm_segments) / scale
    finger_clearance = min(_segment_distance(shape[tip], shape[a], shape[b])
                           for tip in (4, 8) for a, b in finger_segments) / scale
    pinch_shape = all(curled[1:]) and ratios[0] >= 0.45
    if image and world_gap is not None and world_gap > 1.0:
        pinch_shape = False  # Clearly separated in depth, despite 2D overlap.
    thumb_up = False
    thumb_tilt = None
    thumb_vertical = False
    if image:
        # Camera-frame vertical, corrected for aspect ratio. Check the whole
        # thumb and its last segment so a bent/sideways tip cannot sneak through.
        thumb_tilt = max(degrees(atan2(abs(image[4][0] - image[base][0]),
                                      image[base][1] - image[4][1])) for base in (2, 3))
        thumb_vertical = (thumb_tilt <= THUMB_MAX_TILT
                          and image[3][1] - image[4][1] >= 0.10 * contact_scale)
        thumb_up = (
            thumb_vertical and _angle(shape[2], shape[3], shape[4]) >= 145
            and image[2][1] - image[4][1] >= 0.45 * contact_scale
            and image[5][1] - image[4][1] >= 0.20 * contact_scale
            and sum(ratio < 0.70 for ratio in ratios) >= 3
            and sum(extended) <= 1
        )
    return {"gap": gap, "world_gap": world_gap, "extended": extended,
            "min_tip_gap": min_tip_gap, "closest_tips": f"{closest_a}-{closest_b}",
            "curled": curled, "index_reach": index_reach,
            "thumb_reach": thumb_reach, "palm_clearance": palm_clearance,
            "finger_clearance": finger_clearance,
            "approach_angle": approach_angle, "thumb_tilt": thumb_tilt,
            "thumb_vertical": thumb_vertical,
            "ratios": ratios, "pinch_shape": pinch_shape, "thumb_up": thumb_up}


def _pinch_blockers(features):
    if features is None:
        return ["landmarks"]
    blockers = [] if features["pinch_shape"] else ["curl_or_depth"]
    for field, minimum in (("index_reach", PINCH_INDEX_REACH),
                           ("palm_clearance", PINCH_PALM_CLEARANCE),
                           ("thumb_reach", PINCH_THUMB_REACH),
                           ("finger_clearance", PINCH_FINGER_CLEARANCE)):
        if features[field] < minimum:
            blockers.append(field)
    return blockers


def _pinch(features):
    if _pinch_blockers(features):
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


def _thumbs_up_allowed(features):
    # Shared by the canned model and geometric fallback. A foreshortened fist
    # can look upright in 2D; touching thumb/index tips must not become thumbs-up.
    return (features is not None and features["thumb_vertical"]
            and features["thumb_tilt"] is not None
            and features["thumb_tilt"] <= THUMB_MAX_TILT
            and features["gap"] >= THUMB_MIN_GAP)


def _open_palm_blockers(features):
    if features is None:
        return ["landmarks"]
    blockers = []
    if features["gap"] < OPEN_THUMB_INDEX_GAP:
        blockers.append("thumb_index_gap")
    if features["min_tip_gap"] < OPEN_MIN_TIP_GAP:
        blockers.append("finger_separation")
    return blockers


def _compact_fist(features):
    # Support a weaker Closed_Fist model vote only with positive compact-hand
    # evidence. Short reach and low clearance keep this separate from PINCH.
    return (features is not None and not any(features["extended"])
            and all(features["curled"][1:])
            and features["gap"] <= 0.65
            and features["index_reach"] <= 0.65
            and features["palm_clearance"] <= 0.60
            and features["finger_clearance"] <= 0.35)


def analyze_gesture(categories, world_landmarks=(), image_landmarks=(), aspect=1.0):
    features = measure_hand(world_landmarks, image_landmarks, aspect)
    valid = [c for c in categories if isfinite(c.score) and 0 <= c.score <= 1]
    best = max(valid, key=lambda c: c.score) if valid else None
    fist_support = _compact_fist(features)
    recognized = Gesture()
    if best is not None:
        name = GESTURE_LABELS.get(best.category_name)
        threshold = SUPPORTED_FIST_THRESHOLD if name == "FIST" and fist_support else MODEL_THRESHOLDS.get(name, 1.0)
        if name and best.score >= threshold:
            recognized = Gesture(name, float(best.score))
    # The canned class accepts tilted thumbs. Every recognition path must obey
    # the game's stricter vertical rule; without image landmarks it is unknown.
    thumb_allowed = _thumbs_up_allowed(features)
    thumb_shape = thumb_allowed and features["thumb_up"]
    if recognized.label == "THUMBS_UP" and not thumb_allowed:
        recognized = Gesture()
    open_blockers = _open_palm_blockers(features)
    if recognized.label == "OPEN_PALM" and open_blockers:
        recognized = Gesture()
    pinch = _pinch(features)
    # The requested closed-hand pinch may get a canned Closed_Fist label. Let
    # the more specific all-finger geometry distinguish it from an ordinary fist.
    if pinch.label == "PINCH":
        gesture = pinch
    elif recognized.label == "FIST":
        gesture = recognized
    elif thumb_shape:
        gesture = Gesture("THUMBS_UP", max(0.8, recognized.confidence if recognized.label == "THUMBS_UP" else 0))
    elif not open_blockers and all(features["extended"]):
        gesture = Gesture("OPEN_PALM", max(0.8, recognized.confidence if recognized.label == "OPEN_PALM" else 0))
    else:
        gesture = recognized
    details = f"model={best.category_name}:{best.score:.2f}" if best else "model=none"
    if features is not None:
        world_text = f"{features['world_gap']:.2f}" if features["world_gap"] is not None else "n/a"
        details += f" gap={features['gap']:.2f} gap3d={world_text} extended={sum(features['extended'])}"
        details += f" curled={sum(features['curled'][1:])}/3 index_reach={features['index_reach']:.2f}"
        details += f" thumb_reach={features['thumb_reach']:.2f} palm_clearance={features['palm_clearance']:.2f}"
        details += f" finger_clearance={features['finger_clearance']:.2f}"
        tilt_text = f"{features['thumb_tilt']:.1f}" if features["thumb_tilt"] is not None else "n/a"
        details += f" approach_angle={features['approach_angle']:.1f} thumb_tilt={tilt_text}"
        blockers = _pinch_blockers(features)
        details += f" pinch_shape={int(not blockers)} thumb_allowed={int(thumb_allowed)}"
        if features["gap"] > PINCH_RELEASE:
            blockers.append("tip_gap")
        details += f" pinch_block={','.join(blockers) or 'none'}"
        details += f" min_tip_gap={features['min_tip_gap']:.2f} closest_tips={features['closest_tips']}"
        details += f" open_block={','.join(open_blockers) or 'none'}"
        details += f" fist_support={int(fist_support)}"
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
