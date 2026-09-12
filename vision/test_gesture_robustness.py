"""Regression cases for geometric fallbacks, depth noise, and label flicker.

Synthetic shapes exercise decisions; they do not establish live model accuracy.
"""

from types import SimpleNamespace as Point
import unittest

from gestures import Gesture, GestureDebouncer, classify_gesture, measure_hand


def hand_shape(kind, mirror=1, scale=1, aspect=4 / 3):
    points = [[0.0, 0.0, 0.0] for _ in range(21)]
    for base, x, y in ((5, -0.4, -0.8), (9, 0, -0.9), (13, 0.3, -0.8), (17, 0.6, -0.7)):
        offsets = (0, -0.4, -0.7, -1.0) if kind in ("open", "open_pinch") else (0, -0.25, 0.02, 0.18)
        for offset, dy in enumerate(offsets):
            points[base + offset] = [x, y + dy, 0]
    points[1:5] = [[-0.3, -0.15, 0], [-0.6, -0.3, 0], [-1.0, -0.5, 0], [-1.3, -0.7, 0]]
    if kind in ("thumb_up", "thumb_down"):
        direction = -1 if kind == "thumb_up" else 1
        points[2:5] = [[-0.8, -0.35, 0], [-0.8, -0.35 + direction * 0.65, 0],
                       [-0.8, -0.35 + direction * 1.4, 0]]
    if kind == "loose_pinch":
        for base in (9, 13, 17):
            x, y, _ = points[base]
            for offset, (dx, dy) in enumerate(((0, 0), (0, -0.4), (0.28, -0.6), (0.4, -0.5))):
                points[base + offset] = [x + dx, y + dy, 0]
    if kind in ("pinch", "open_pinch", "loose_pinch"):
        points[6:9] = [[-0.4, -1.2, 0], [-0.6, -1.3, 0], [-0.7, -1.2, 0]]
        points[2:5] = [[-0.55, -0.4, 0], [-0.8, -0.8, 0], [-0.69, -1.2, 0]]
    if kind == "fist":
        points[4] = [-0.4, -0.6, 0]
    world = [Point(x=x * mirror * scale, y=y * scale, z=z * scale) for x, y, z in points]
    image = [Point(x=0.5 + x * mirror * scale * 0.15 / aspect,
                   y=0.5 + y * scale * 0.15, z=z) for x, y, z in points]
    return world, image


class GestureRobustnessTests(unittest.TestCase):
    def test_loose_pinch_accepts_fingertips_beyond_palm(self):
        for mirror in (-1, 1):
            for scale in (0.4, 1.0):
                for aspect in (4 / 3, 16 / 9):
                    world, image = hand_shape("loose_pinch", mirror, scale, aspect)
                    for shape_world, shape_image in ((world, image), (world, ()), ((), image)):
                        with self.subTest(mirror=mirror, scale=scale, aspect=aspect,
                                          world=bool(shape_world), image=bool(shape_image)):
                            features = measure_hand(shape_world, shape_image, aspect)
                            self.assertTrue(all(features["curled"][1:]))
                            self.assertEqual(classify_gesture([], shape_world, shape_image, aspect).label, "PINCH")

    def test_closed_hand_pinch_accepts_both_hands_at_different_scales(self):
        for mirror in (-1, 1):
            for scale in (0.4, 1.0):
                world, image = hand_shape("pinch", mirror, scale)
                features = measure_hand(world, image, 4 / 3)
                self.assertTrue(all(features["curled"][1:]))
                self.assertEqual(classify_gesture([], world, image, 4 / 3).label, "PINCH")

    def test_open_pinch_and_each_extended_supporting_finger_are_rejected(self):
        for mirror in (-1, 1):
            world_open, image_open = hand_shape("open_pinch", mirror)
            self.assertNotEqual(classify_gesture([], world_open, image_open, 4 / 3).label, "PINCH")
            for base in (9, 13, 17):
                with self.subTest(mirror=mirror, base=base):
                    world, image = hand_shape("pinch", mirror)
                    world[base:base + 4] = world_open[base:base + 4]
                    image[base:base + 4] = image_open[base:base + 4]
                    self.assertNotEqual(classify_gesture([], world, image, 4 / 3).label, "PINCH")

    def test_degenerate_supporting_finger_is_not_assumed_curled(self):
        world, image = hand_shape("pinch")
        world[13:17] = [world[13]] * 4
        image[13:17] = [image[13]] * 4
        self.assertNotEqual(classify_gesture([], world, image, 4 / 3).label, "PINCH")

    def test_opening_supporting_fingers_clears_stabilized_pinch(self):
        world, image = hand_shape("pinch")
        closed = classify_gesture([], world, image, 4 / 3)
        world, image = hand_shape("open_pinch")
        opened = classify_gesture([], world, image, 4 / 3)
        tracker = GestureDebouncer()
        tracker.update([closed, Gesture()], 0, [True, False])
        self.assertEqual(tracker.update([closed, Gesture()], 0.05, [True, False])[0].label, "PINCH")
        tracker.update([opened, Gesture()], 0.08, [True, False])
        self.assertNotEqual(tracker.update([opened, Gesture()], 0.16, [True, False])[0].label, "PINCH")

    def test_open_palm_fallback_for_both_hands_and_image_aspects(self):
        for mirror in (-1, 1):
            for aspect in (4 / 3, 16 / 9):
                world, image = hand_shape("open", mirror, 0.5, aspect)
                self.assertEqual(classify_gesture([], world, image, aspect).label, "OPEN_PALM")

    def test_thumbs_up_fallback_and_thumbs_down_rejection(self):
        for mirror in (-1, 1):
            world, image = hand_shape("thumb_up", mirror)
            self.assertEqual(classify_gesture([], world, image, 4 / 3).label, "THUMBS_UP")
            world, image = hand_shape("thumb_down", mirror)
            self.assertNotEqual(classify_gesture([], world, image, 4 / 3).label, "THUMBS_UP")

    def test_moderate_model_scores_accept_palm_and_thumb_but_not_fist(self):
        for model, expected in (("Open_Palm", "OPEN_PALM"), ("Thumb_Up", "THUMBS_UP"),
                                ("Closed_Fist", "UNKNOWN")):
            self.assertEqual(classify_gesture([Point(category_name=model, score=0.6)]).label, expected)

    def test_touching_tips_survive_moderate_world_depth_noise(self):
        for mirror in (-1, 1):
            world, image = hand_shape("pinch", mirror)
            world[4].z += 0.4  # Old 0.22 3D gap rule rejected this.
            self.assertEqual(classify_gesture([], world, image, 4 / 3).label, "PINCH")

    def test_clear_pinch_not_blocked_by_canned_fist_label(self):
        world, image = hand_shape("pinch")
        result = classify_gesture([Point(category_name="Closed_Fist", score=0.9)], world, image, 4 / 3)
        self.assertEqual(result.label, "PINCH")

    def test_closed_fist_not_reinterpreted_as_pinch(self):
        world, image = hand_shape("fist")
        result = classify_gesture([Point(category_name="Closed_Fist", score=0.9)], world, image, 4 / 3)
        self.assertEqual(result.label, "FIST")

    def test_projection_overlap_at_large_depth_separation_rejected(self):
        world, image = hand_shape("pinch")
        world[4].z = 2
        self.assertNotEqual(classify_gesture([], world, image, 4 / 3).label, "PINCH")

    def test_weak_pinch_retains_but_cannot_activate(self):
        world, image = hand_shape("pinch")
        image[4].x = image[8].x + 0.37 * 0.15 / (4 / 3)
        weak = classify_gesture([], world, image, 4 / 3)
        self.assertEqual(weak.label, "PINCH")
        self.assertLess(weak.confidence, 0.55)
        tracker = GestureDebouncer()
        for t in (0, 0.05, 0.1):
            self.assertEqual(tracker.update([weak, Gesture()], t, [True, False])[0].label, "UNKNOWN")
        strong = Gesture("PINCH", 0.9)
        tracker.update([strong, Gesture()], 0.15, [True, False])
        self.assertEqual(tracker.update([strong, Gesture()], 0.20, [True, False])[0].label, "PINCH")
        self.assertEqual(tracker.update([weak, Gesture()], 0.25, [True, False])[0].label, "PINCH")

    def test_present_hand_bridges_score_dip_but_expires(self):
        tracker = GestureDebouncer()
        pose = [Gesture("OPEN_PALM", 0.9), Gesture("THUMBS_UP", 0.8)]
        tracker.update(pose, 0, [True, True])
        tracker.update(pose, 0.05, [True, True])
        held = tracker.update([Gesture(), pose[1]], 0.08, [True, True])
        self.assertEqual(held[0].label, "OPEN_PALM")
        self.assertLess(held[0].confidence, 0.9)
        self.assertEqual(held[1], pose[1])
        self.assertEqual(tracker.update([Gesture(), pose[1]], 0.16, [True, True])[0].label, "UNKNOWN")

    def test_missing_hand_clears_without_grace_period(self):
        tracker = GestureDebouncer()
        pose = [Gesture("PINCH", 0.9), Gesture()]
        tracker.update(pose, 0, [True, False])
        tracker.update(pose, 0.05, [True, False])
        self.assertEqual(tracker.update([Gesture(), Gesture()], 0.06, [False, False])[0], Gesture())

    def test_unknown_dip_does_not_restart_initial_confirmation(self):
        tracker = GestureDebouncer()
        pose = [Gesture("OPEN_PALM", 0.9), Gesture()]
        tracker.update(pose, 0, [True, False])
        tracker.update([Gesture(), Gesture()], 0.02, [True, False])
        self.assertEqual(tracker.update(pose, 0.05, [True, False])[0], pose[0])


if __name__ == "__main__":
    unittest.main()
