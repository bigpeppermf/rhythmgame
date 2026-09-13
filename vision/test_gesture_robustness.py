"""Regression cases for geometric fallbacks, depth noise, and label flicker.

Synthetic shapes exercise decisions; they do not establish live model accuracy.
"""

from types import SimpleNamespace as Point
from math import cos, sin, radians
import unittest
from unittest.mock import patch

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
    if kind == "compact_pinch":
        points[6:9] = [[-0.4, -1.2, 0], [-0.6, -1.3, 0], [-0.7, -1.2, 0]]
        points[2:5] = [[-0.55, -0.4, 0], [-0.8, -0.8, 0], [-0.69, -1.2, 0]]
    if kind in ("pinch", "open_pinch", "loose_pinch"):
        # Deliberate pinch reaches clear of the palm and the curled fingers.
        points[6:9] = [[-0.4, -1.35, 0], [-0.7, -1.55, 0], [-0.9, -1.5, 0]]
        points[2:5] = [[-0.55, -0.4, 0], [-0.8, -0.8, 0], [-0.89, -1.5, 0]]
    if kind == "raised_fist":
        # Thumb lies over a slightly raised index: touching tips and enough
        # index reach to pass the old rule, but still close to the palm.
        points[6:9] = [[-0.4, -1.25, 0], [-0.4, -1.23, 0], [-0.4, -1.17, 0]]
        points[4] = [-0.39, -1.17, 0]
    if kind == "fist":
        points[4] = [-0.4, -0.6, 0]
    world = [Point(x=x * mirror * scale, y=y * scale, z=z * scale) for x, y, z in points]
    image = [Point(x=0.5 + x * mirror * scale * 0.15 / aspect,
                   y=0.5 + y * scale * 0.15, z=z) for x, y, z in points]
    return world, image


class GestureRobustnessTests(unittest.TestCase):
    def test_reported_good_fists_with_moderate_model_scores(self):
        # Logged measurements replay classification, not landmark inference.
        readings = (
            (.77, .35, .33, .39, .76, .36, .22, 129.0, 23.7, .21),
            (.83, .33, .41, .37, .76, .31, .24, 148.3, 41.4, .20),
            (.84, .41, .45, .56, .85, .54, .18, 103.4, 41.8, .21),
            (.74, .35, .42, .38, .73, .35, .12, 116.1, 56.0, .15),
            (.74, .54, .54, .50, .82, .48, .09, 113.3, 43.0, .22),
            (.57, .47, .49, .43, .74, .42, .04, 102.9, 60.9, .18),
            (.75, .56, .55, .52, .83, .49, .11, 110.7, 43.3, .24),
            (.61, .50, .50, .43, .74, .43, .04, 102.2, 60.1, .21),
        )
        tracker = GestureDebouncer()
        for frame, (score, gap, depth, index, thumb, palm, fingers, angle, tilt, minimum) in enumerate(readings):
            features = dict(gap=gap, world_gap=depth, index_reach=index, thumb_reach=thumb,
                            palm_clearance=palm, finger_clearance=fingers, approach_angle=angle,
                            thumb_tilt=tilt, min_tip_gap=minimum, closest_tips="16-20",
                            extended=[False] * 4, curled=[False, True, True, True],
                            pinch_shape=True, thumb_vertical=False, thumb_up=False)
            with self.subTest(score=score), patch("gestures.measure_hand", return_value=features):
                result = classify_gesture([Point(category_name="Closed_Fist", score=score)])
                self.assertEqual(result, Gesture("FIST", score))
                # Lower-score examples must also be able to initiate a fist.
                fresh = GestureDebouncer()
                fresh.update([result, result], 0, [True, True])
                self.assertEqual(fresh.update([result, result], .05, [True, True]), [result, result])
                stable = tracker.update([result, result], frame * .05, [True, True])
                if frame:
                    self.assertEqual([pose.label for pose in stable], ["FIST", "FIST"])

    def test_supported_fist_requires_model_vote_and_compact_geometry(self):
        for mirror in (-1, 1):
            world, image = hand_shape("fist", mirror)
            # Rest the thumb across the curled middle/index fingers, supplying
            # positive proximity evidence for the lower model-score path.
            world[4] = Point(x=-.15 * mirror, y=-.65, z=0)
            image[4] = Point(x=.5 - .15 * mirror * .15 / (4 / 3), y=.5 - .65 * .15, z=0)
            for score in (.54, .55, .57, .61, .69):
                model = [Point(category_name="Closed_Fist", score=score)]
                with self.subTest(mirror=mirror, score=score):
                    result = classify_gesture(model, world, image, 4 / 3)
                    self.assertEqual(result.label, "FIST" if score >= .55 else "UNKNOWN")
            self.assertEqual(classify_gesture([], world, image, 4 / 3).label, "UNKNOWN")
            self.assertEqual(classify_gesture([Point(category_name="None", score=.99)], world, image, 4 / 3).label, "UNKNOWN")
            features = measure_hand(world, image, 4 / 3)
            features.update(gap=1.09, thumb_vertical=True, thumb_up=True, thumb_tilt=1.3)
            with patch("gestures.measure_hand", return_value=features):
                # An upright separated thumb can have the same compact finger
                # measurements; a weak canned fist vote must not displace it.
                self.assertEqual(classify_gesture([Point(category_name="Closed_Fist", score=.61)]).label, "THUMBS_UP")
            # Invalid supporting-finger landmarks cannot lower the threshold.
            world[13:17] = [world[13]] * 4
            image[13:17] = [image[13]] * 4
            self.assertEqual(classify_gesture([Point(category_name="Closed_Fist", score=.61)], world, image, 4 / 3).label, "UNKNOWN")
            for kind in ("open", "pinch", "thumb_up"):
                world, image = hand_shape(kind, mirror)
                self.assertNotEqual(classify_gesture([Point(category_name="Closed_Fist", score=.61)], world, image, 4 / 3).label, "FIST")

    def test_any_touching_fingertip_pair_blocks_open_palm(self):
        tips = (4, 8, 12, 16, 20)
        for mirror in (-1, 1):
            for aspect in (4 / 3, 16 / 9):
                for i, a in enumerate(tips):
                    for b in tips[i + 1:]:
                        world, image = hand_shape("open", mirror, .6, aspect)
                        world[a], image[a] = world[b], image[b]
                        for categories in ([], [Point(category_name="Open_Palm", score=.99)]):
                            with self.subTest(mirror=mirror, aspect=aspect, pair=(a, b), model=bool(categories)):
                                self.assertEqual(classify_gesture(categories, world, image, aspect).label, "UNKNOWN")

    def test_reported_thumb_index_gaps_block_four_extended_finger_fallback(self):
        # Replay the logged gaps on synthetic four-extended-finger shapes. No
        # raw landmarks were attached, so this does not replay tracker inference.
        gaps = (.34, .20, .22, .26, .17, .18, .22, .13, .21, .24, .24, .22, .17, .19)
        for mirror in (-1, 1):
            for scale in (.4, 1.0):
                for gap in gaps:
                    world, image = hand_shape("open", mirror, scale)
                    image[4] = Point(x=image[8].x + mirror * gap * scale * .15 / (4 / 3),
                                     y=image[8].y, z=0)
                    # Inferred depth can disagree with visible contact; it must
                    # not rescue OPEN_PALM when the image tips are close.
                    world[4] = Point(x=world[8].x, y=world[8].y, z=.92 * scale)
                    with self.subTest(mirror=mirror, scale=scale, gap=gap):
                        self.assertTrue(all(measure_hand(world, image, 4 / 3)["extended"]))
                        for categories in ([], [Point(category_name="Open_Palm", score=.99)]):
                            self.assertEqual(classify_gesture(categories, world, image, 4 / 3).label, "UNKNOWN")

    def test_touching_then_separating_tips_clears_and_restores_open_palm(self):
        world, image = hand_shape("open")
        model = [Point(category_name="Open_Palm", score=.99)]
        opened = classify_gesture(model, world, image, 4 / 3)
        world[4], image[4] = world[8], image[8]
        touching = classify_gesture(model, world, image, 4 / 3)
        tracker = GestureDebouncer()
        tracker.update([opened, opened], 0, [True, True])
        tracker.update([opened, opened], .05, [True, True])
        tracker.update([touching, opened], .08, [True, True])
        stable = tracker.update([touching, opened], .16, [True, True])
        self.assertEqual([pose.label for pose in stable], ["UNKNOWN", "OPEN_PALM"])
        tracker.update([opened, opened], .20, [True, True])
        stable = tracker.update([opened, opened], .25, [True, True])
        self.assertEqual([pose.label for pose in stable], ["OPEN_PALM", "OPEN_PALM"])

    def test_reported_loose_fists_and_good_pinches(self):
        # Recorded scalar readings; inference itself cannot be replayed without
        # landmarks. Use permissive unlogged predicates to challenge rejection.
        # model, score, gap, 3D gap, index, thumb, palm, fingers, approach, tilt, good
        samples = (
            ("Closed_Fist", .72, .08, .15, .48, .66, .45, .20, 118.8, 75.9, False),
            ("Closed_Fist", .56, .05, .15, .59, .71, .48, .25, 112.7, 40.0, False),
            ("Closed_Fist", .64, .05, .13, .54, .68, .47, .22, 116.3, 58.9, False),
            ("Closed_Fist", .73, .09, .15, .46, .66, .45, .20, 120.5, 78.5, False),
            ("Closed_Fist", .67, .10, .15, .51, .65, .45, .20, 120.5, 61.0, False),
            ("None", .73, .05, .32, .70, .74, .45, .34, 102.1, 26.0, False),
            ("Closed_Fist", .70, .06, .12, .49, .66, .46, .21, 119.3, 74.2, False),
            ("Closed_Fist", .75, .10, .18, .42, .67, .41, .20, 126.2, 77.6, False),
            ("Closed_Fist", .74, .11, .17, .45, .66, .44, .19, 125.8, 73.7, False),
            ("Closed_Fist", .74, .11, .17, .45, .66, .44, .19, 125.4, 78.1, False),
            ("Closed_Fist", .73, .09, .13, .44, .66, .43, .21, 124.2, 77.7, False),
            ("None", .86, .15, .58, .88, .79, .66, .55, 89.0, 54.9, True),
            ("None", .93, .14, .84, 1.07, .80, .79, .65, 94.1, 61.7, True),
            ("None", .91, .23, .87, 1.09, .77, .76, .80, 58.7, 68.7, True),
        )
        for model, score, gap, gap3d, index, thumb, palm, fingers, angle, tilt, good in samples:
            features = dict(gap=gap, world_gap=gap3d, index_reach=index, thumb_reach=thumb,
                            palm_clearance=palm, finger_clearance=fingers, approach_angle=angle,
                            thumb_tilt=tilt, extended=[good, False, False, False],
                            curled=[not good, True, True, True], pinch_shape=True,
                            min_tip_gap=min(gap, .2), closest_tips="4-8",
                            thumb_vertical=False, thumb_up=False)
            with self.subTest(model=model, score=score, angle=angle), patch("gestures.measure_hand", return_value=features):
                result = classify_gesture([Point(category_name=model, score=score)])
                expected = "PINCH" if good else "FIST" if model == "Closed_Fist" else "UNKNOWN"
                self.assertEqual(result.label, expected)
                tracker = GestureDebouncer()
                for timestamp in (0, .05, .10, .15):
                    stable = tracker.update([result, result], timestamp, [True, True])
                self.assertEqual([hand.label for hand in stable], [expected, expected])

    def test_low_approach_angle_does_not_block_outward_pinch(self):
        for mirror in (-1, 1):
            world, _ = hand_shape("pinch", mirror)
            world[7] = Point(x=world[8].x - .2 * mirror, y=world[8].y, z=0)
            world[3] = Point(x=world[4].x - .4 * cos(radians(58.7)) * mirror,
                             y=world[4].y + .4 * sin(radians(58.7)), z=0)
            image = [Point(x=.5 + p.x * .15 / (4 / 3), y=.5 + p.y * .15, z=0) for p in world]
            with self.subTest(mirror=mirror):
                self.assertAlmostEqual(measure_hand(world, image, 4 / 3)["approach_angle"], 58.7)
                self.assertEqual(classify_gesture([], world, image, 4 / 3).label, "PINCH")

    def test_reported_live_measurements_at_decision_boundary(self):
        # These are the user's logged scalar measurements, not recorded 21-point
        # landmarks. Unlogged shape predicates are deliberately permissive: test
        # the reported decision failures without pretending to replay inference.
        samples = (
            ("touching fist", "None", 0.92, 0.19, 0.29, 0.94, 0.88, 0.70, 0.45, 73.7, 4.7, "UNKNOWN"),
            # Accepting the later good 21.2-degree readings necessarily also
            # accepts this earlier 7.7-degree pose under the same angle rule.
            ("tilted thumb", "Thumb_Up", 0.82, 0.97, 0.90, 0.63, 0.80, 0.42, 0.20, 159.3, 7.7, "THUMBS_UP"),
            ("pinch first", "None", 0.89, 0.13, 0.88, 0.91, 1.07, 0.83, 0.56, 103.8, 45.1, "PINCH"),
            ("pinch second", "None", 0.90, 0.13, 0.84, 0.92, 1.05, 0.82, 0.58, 102.0, 46.0, "PINCH"),
        )
        for name, model, score, gap, gap3d, index, thumb, palm, fingers, angle, tilt, expected in samples:
            features = dict(gap=gap, world_gap=gap3d, index_reach=index, thumb_reach=thumb,
                            palm_clearance=palm, finger_clearance=fingers, approach_angle=angle,
                            thumb_tilt=tilt, extended=[model != "Thumb_Up", False, False, False],
                            curled=[False, True, True, True], pinch_shape=True,
                            min_tip_gap=min(gap, .2), closest_tips="4-8",
                            thumb_vertical=True, thumb_up=True)
            with self.subTest(name=name), patch("gestures.measure_hand", return_value=features):
                result = classify_gesture([Point(category_name=model, score=score)])
                self.assertEqual(result.label, expected)

    def test_touching_index_cannot_become_thumbs_up_through_any_path(self):
        for mirror in (-1, 1):
            world, image = hand_shape("thumb_up", mirror)
            world[8], image[8] = world[4], image[4]
            for categories in ([], [Point(category_name="Thumb_Up", score=0.99)],
                               [Point(category_name="Closed_Fist", score=0.95)]):
                with self.subTest(mirror=mirror, model=categories):
                    result = classify_gesture(categories, world, image, 4 / 3)
                    self.assertNotEqual(result.label, "THUMBS_UP")

    def test_looser_opposing_tip_angle_accepts_pinch_landmarks(self):
        for mirror in (-1, 1):
            world, _ = hand_shape("pinch", mirror)
            # Index distal segment points right; thumb approaches at 102 degrees.
            world[7] = Point(x=world[8].x - 0.2 * mirror, y=world[8].y, z=0)
            world[3] = Point(x=world[4].x - 0.4 * cos(radians(102)) * mirror,
                             y=world[4].y + 0.4 * sin(radians(102)), z=0)
            image = [Point(x=0.5 + p.x * 0.15 / (4 / 3), y=0.5 + p.y * 0.15, z=0)
                     for p in world]
            with self.subTest(mirror=mirror):
                self.assertAlmostEqual(measure_hand(world, image, 4 / 3)["approach_angle"], 102)
                self.assertEqual(classify_gesture([], world, image, 4 / 3).label, "PINCH")

    def test_thumb_over_looser_index_cannot_override_fist(self):
        for mirror in (-1, 1):
            for scale in (0.4, 1.0):
                for aspect in (4 / 3, 16 / 9):
                    world, image = hand_shape("compact_pinch", mirror, scale, aspect)
                    # Keep touching, outward tips, but let the index's final
                    # segment point alongside the thumb, as in an overlapping fist.
                    world[7] = Point(x=-0.71 * mirror * scale, y=-1.0 * scale, z=0)
                    image[7] = Point(x=0.5 - 0.71 * mirror * scale * 0.15 / aspect,
                                     y=0.5 - scale * 0.15, z=0)
                    for shape_world, shape_image in ((world, image), (world, ()), ((), image)):
                        with self.subTest(mirror=mirror, scale=scale, aspect=aspect):
                            features = measure_hand(shape_world, shape_image, aspect)
                            self.assertGreater(features["palm_clearance"], 0.45)
                            self.assertGreater(features["thumb_reach"], 0.55)
                            self.assertGreater(features["finger_clearance"], 0.20)
                            self.assertGreater(features["ratios"][0], 0.45)
                            self.assertTrue(all(features["curled"][1:]))
                            self.assertLess(features["gap"], 0.30)
                            for categories in ([], [Point(category_name="Closed_Fist", score=0.95)]):
                                result = classify_gesture(categories, shape_world, shape_image, aspect)
                                self.assertEqual(result.label, "FIST" if categories else "UNKNOWN")

    def test_thumb_direction_gates_model_and_geometry_for_both_hands(self):
        for mirror in (-1, 1):
            for aspect in (4 / 3, 16 / 9):
                for tilt in (-90, -35, -25.1, -24.9, -21.2, -7.7, 0, 7.7, 21.2, 24.9, 25.1, 35, 90, 180):
                    world, _ = hand_shape("thumb_up", mirror)
                    for joint in (3, 4):
                        length = abs(world[joint].y - world[2].y)
                        world[joint] = Point(x=world[2].x + length * sin(radians(tilt)),
                                             y=world[2].y - length * cos(radians(tilt)), z=0)
                    image = [Point(x=0.5 + p.x * 0.15 / aspect, y=0.5 + p.y * 0.15, z=0)
                             for p in world]
                    for categories in ([], [Point(category_name="Thumb_Up", score=0.6)],
                                       [Point(category_name="Thumb_Up", score=0.99)]):
                        with self.subTest(mirror=mirror, aspect=aspect, tilt=tilt, model=bool(categories)):
                            result = classify_gesture(categories, world, image, aspect)
                            self.assertEqual(result.label, "THUMBS_UP" if abs(tilt) <= 25 else "UNKNOWN")

    def test_reported_good_thumb_angles_remain_stable(self):
        # Replay reported angle/score changes on synthetic upright hand shapes;
        # the full landmarks were not recorded, so this is not an inference replay.
        readings = ((21.2, .69), (14.9, .71), (9.9, .73), (1.3, .69), (15.5, .64),
                    (9.5, .70), (3.9, .72), (2.2, .73), (.8, .74), (1.9, .74))
        for aspect in (4 / 3, 16 / 9):
            tracker = GestureDebouncer()
            for frame, (tilt, score) in enumerate(readings):
                poses = []
                for mirror in (-1, 1):
                    world, _ = hand_shape("thumb_up", mirror)
                    for joint in (3, 4):
                        length = abs(world[joint].y - world[2].y)
                        world[joint] = Point(x=world[2].x + mirror * length * sin(radians(tilt)),
                                             y=world[2].y - length * cos(radians(tilt)), z=0)
                    image = [Point(x=.5 + p.x * .15 / aspect, y=.5 + p.y * .15, z=0)
                             for p in world]
                    with self.subTest(frame=frame, mirror=mirror, aspect=aspect):
                        self.assertAlmostEqual(measure_hand(world, image, aspect)["thumb_tilt"], tilt)
                        pose = classify_gesture([Point(category_name="Thumb_Up", score=score)], world, image, aspect)
                        self.assertEqual(pose.label, "THUMBS_UP")
                        poses.append(pose)
                stable = tracker.update(poses, frame * .05, [True, True])
                if frame >= 1:
                    self.assertEqual([pose.label for pose in stable], ["THUMBS_UP", "THUMBS_UP"])

    def test_thumb_tip_tilt_and_missing_image_cannot_bypass_direction_gate(self):
        world, image = hand_shape("thumb_up")
        model = [Point(category_name="Thumb_Up", score=0.99)]
        self.assertEqual(classify_gesture(model, world).label, "UNKNOWN")
        # Whole thumb still vertical; the final segment points sideways.
        image[3].x += 0.05
        self.assertEqual(classify_gesture(model, world, image, 4 / 3).label, "UNKNOWN")

    def test_tilted_thumb_clears_previously_stable_thumbs_up(self):
        world, image = hand_shape("thumb_up")
        model = [Point(category_name="Thumb_Up", score=0.99)]
        upright = classify_gesture(model, world, image, 4 / 3)
        image[4].x += 0.10
        tilted = classify_gesture(model, world, image, 4 / 3)
        tracker = GestureDebouncer()
        tracker.update([upright, Gesture()], 0, [True, False])
        self.assertEqual(tracker.update([upright, Gesture()], 0.05, [True, False])[0].label, "THUMBS_UP")
        tracker.update([tilted, Gesture()], 0.08, [True, False])
        self.assertEqual(tracker.update([tilted, Gesture()], 0.16, [True, False])[0].label, "UNKNOWN")

    def test_thumb_over_raised_index_fist_is_not_pinch(self):
        for mirror in (-1, 1):
            for scale in (0.4, 1.0):
                world, image = hand_shape("raised_fist", mirror, scale)
                for shape_world, shape_image in ((world, image), (world, ()), ((), image)):
                    with self.subTest(mirror=mirror, scale=scale, world=bool(shape_world)):
                        features = measure_hand(shape_world, shape_image, 4 / 3)
                        # Reproduce a pose that satisfied the previous pinch gate.
                        self.assertGreater(features["index_reach"], 0.35)
                        self.assertGreater(features["ratios"][0], 0.45)
                        self.assertTrue(all(features["curled"][1:]))
                        self.assertLess(features["gap"], 0.30)
                        for categories in ([], [Point(category_name="Closed_Fist", score=0.9)]):
                            result = classify_gesture(categories, shape_world, shape_image, 4 / 3)
                            self.assertEqual(result.label, "FIST" if categories else "UNKNOWN")

    def test_reach_checks_are_invariant_to_hand_rotation(self):
        for kind in ("pinch", "loose_pinch", "raised_fist"):
            for angle in (0.6, 1.5, 3.0):
                world, _ = hand_shape(kind)
                rotated = [Point(x=p.x * cos(angle) - p.y * sin(angle),
                                 y=p.x * sin(angle) + p.y * cos(angle), z=p.z) for p in world]
                image = [Point(x=0.5 + p.x * 0.15 / (4 / 3), y=0.5 + p.y * 0.15, z=0)
                         for p in rotated]
                with self.subTest(kind=kind, angle=angle):
                    result = classify_gesture([], rotated, image, 4 / 3)
                    self.assertEqual(result.label, "UNKNOWN" if kind == "raised_fist" else "PINCH")

    def test_pinch_to_raised_fist_clears_stable_pinch(self):
        world, image = hand_shape("pinch")
        pinch = classify_gesture([], world, image, 4 / 3)
        world, image = hand_shape("raised_fist")
        fist = classify_gesture([Point(category_name="Closed_Fist", score=0.9)], world, image, 4 / 3)
        tracker = GestureDebouncer()
        tracker.update([pinch, Gesture()], 0, [True, False])
        self.assertEqual(tracker.update([pinch, Gesture()], 0.05, [True, False])[0].label, "PINCH")
        tracker.update([fist, Gesture()], 0.08, [True, False])
        self.assertEqual(tracker.update([fist, Gesture()], 0.13, [True, False])[0].label, "FIST")

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
                for scale in (.4, 1.0):
                    world, image = hand_shape("open", mirror, scale, aspect)
                    for shape_world, shape_image in ((world, image), (world, ()), ((), image)):
                        for categories in ([], [Point(category_name="Open_Palm", score=.99)]):
                            self.assertEqual(classify_gesture(categories, shape_world, shape_image, aspect).label, "OPEN_PALM")

    def test_thumbs_up_fallback_and_thumbs_down_rejection(self):
        for mirror in (-1, 1):
            world, image = hand_shape("thumb_up", mirror)
            self.assertEqual(classify_gesture([], world, image, 4 / 3).label, "THUMBS_UP")
            world, image = hand_shape("thumb_down", mirror)
            self.assertNotEqual(classify_gesture([], world, image, 4 / 3).label, "THUMBS_UP")

    def test_moderate_model_scores_accept_palm_and_thumb_but_not_fist(self):
        for model, expected in (("Open_Palm", "UNKNOWN"), ("Thumb_Up", "UNKNOWN"),
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
