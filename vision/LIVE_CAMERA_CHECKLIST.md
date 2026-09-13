# Live camera checklist

Check a box only after observing the expected result. Leave failures unchecked
and record what happened below. These are manual acceptance tests; automated
tests do not establish live tracking accuracy or latency.

## Setup

From `rhythmgame` with your venv activated, start the demo with the camera debug window
(or prefix either command below with `uv run`):

```bash
python vision/vertical_demo.py --debug
```

For UDP tests, start a second terminal in the same directory:

```bash
python vision/udp_receiver.py
```

Use **D** to toggle debug, **R** to retry a paused detector, **Q/Esc** in an OpenCV window to quit the demo,
and **Ctrl+C** in the receiver terminal to stop the receiver. Capture threading
is automatic for a live webcam. Start with only the player visible and allow
5 seconds for startup and FPS measurements before judging performance.

Only hands need to be in view; sit normally with the camera aimed at your hand
area. No torso selection or calibration is required. **C** clears hand/gesture
history and restarts the short handedness confirmation.

## Seated play and strict anatomical slots

- [ ] **Seated startup:** keep shoulders/hips outside the camera view. Show your
  hands; they start controlling their slots without clicking or calibrating.
- [ ] **Left only:** move your physical left hand throughout the image, including
  the right side. Only the left slot can be TRACKED. Repeat for physical right.
- [ ] **Recently missing left:** track both hands, hide left, then move your right
  into the left hand's old position. The right must never drive the left slot.
  Repeat with sides reversed. Record candidate labels/scores if this fails.
- [ ] **Fist/pinch label changes:** turn hands side-on and make gestures. A wrong
  or uncertain handedness label should be rejected, not accepted by proximity.
  Use `slot_check` and `candidates` to distinguish slot rejection from gesture errors.
- [ ] **Palm/back/rotation:** rotate each hand, show its back, and fold the thumb.
  Check physical handedness directly; horizontal thumb position alone is not a
  valid anatomical rule. Record any confidently wrong model label.
- [ ] **Long absence:** hide either/both hands for 5 seconds and return them at a
  new position. Correctly labeled hands recover after about 60 ms of consistent
  matches without C. Missing gestures remain UNKNOWN.
- [ ] **Brief label uncertainty:** after an uncertain frame, recovery requires
  confirmation again. Once confirmed, motion should update on every fresh frame.
- [ ] **Reset:** press C. Cursor/gesture histories clear and new observations must
  confirm again; no old gesture should survive the reset.

## Basic control and handedness

- [ ] **Left alone:** show only your anatomical left palm and move it vertically
  ten times. Only the left cursor follows. Repeat after removing it for 1 second.
- [ ] **Right alone:** repeat with your right palm. Only the right cursor follows.
- [ ] **Independent movement:** move the left up while moving the right down,
  then reverse ten times. Neither cursor follows the opposite hand.
- [ ] **Stationary palms:** hold both still for 10 seconds. They stay TRACKED.
  Record the approximate range of displayed y values to measure jitter; some
  jitter is expected before smoothing is added.
- [ ] **Fast motion and reversals:** move up/down quickly within comfortable
  reach for 20 seconds, then stop. Look for delayed following, repeated losses,
  or a cursor that continues moving through old positions after you stop.
- [ ] **Hand orientation:** rotate each palm slightly and turn it sideways, then
  return to facing the camera. Record which orientations lose tracking or swap
  slots; restored palms should reacquire the correct lane.
- [ ] **Crossing:** cross and uncross your hands ten times. Desired behavior:
  identity is preserved, or uncertainty causes temporary loss rather than a
  confident swap. Full overlap is a known difficult case, not a guaranteed pass.

## Tracking loss and recovery

- [ ] **Hide left:** keep the right visible; remove the left for 1 second. Left
  briefly holds/fades as COASTING, then becomes LOST; right continues normally.
- [ ] **Hide right:** repeat with the opposite hand and check independent states.
- [ ] **Reacquisition:** show the missing palm again. It returns to its correct
  slot. First-sample velocity resets to zero (the display may update too quickly
  to see that one frame; the automated tests cover the exact reset).
- [ ] **Both absent:** remove both hands for 2 seconds. Both lanes remain LOST
  with confidence 0. No background object should sustain TRACKED state.

The COASTING period is only 200 ms and can be hard to see. Do not use terminal
print frequency to measure it: the diagnostic receiver prints only at 5 Hz.

## Other people / handedness limitations

- [ ] **Opposite-side bystander:** hide your left while someone shows their right
  near its old position. A Right-labeled candidate must never drive the left slot.
  Repeat for the other side; record physical hand and candidate label separately.
- [ ] **Duplicate same-side hands:** show two left hands, then two right hands.
  When both are confidently detected, that slot should be unavailable with
  `ambiguous_same_side`; the extra hand must never fill the other slot.
- [ ] **Same-side takeover check:** hide your left and show another person's left.
  Record whether it takes over. This remains possible: hand-only left/right
  classification does not establish which person owns the hand.
- [ ] **Background movement:** someone waves from behind/on either side. Record
  missing hands, confidently wrong labels, and same-side takeovers separately.

These checks do not prove player identity. The model detects at most two hands;
a missed player or bystander hand can hide ambiguity. Keep other people's hands
outside the camera's hand area during gameplay until a separate ownership
mechanism suitable for seated play is developed.

## Capture performance and room conditions

- [ ] **Long gesture session:** alternate two-hand gestures for several minutes.
  If the packet-ownership graph error recurs, confirm the terminal announces
  recovery and the windows stay open. During recovery, gestures become UNKNOWN;
  model restart must not replay an old action. Three consecutive failures pause
  detection, with R offered as a retry. Record interruptions and frame delay.
- [ ] **Paused detector retry:** if detection pauses after graph failures, press R.
  Confirm either fresh detection resumes or a visible restart failure remains.
  Returning hands must confirm their handedness before input resumes. This
  manual test is conditional on encountering the failure; do not mark it passed
  merely because the automated injected-failure tests pass.

- [ ] **Baseline:** run for 30 seconds. Record Capture FPS, Loop FPS, Detection ms,
  Wait ms, and the change in Skipped. Use actual readings, not requested 60 FPS.
- [ ] **Sustained run:** play for 3 minutes. Compare readings near the beginning
  and end. Look for increasing delay or persistent frame-rate deterioration.
- [ ] **Debug overhead:** repeat the same movement with debug on and off using D.
  Record any change in Loop FPS and Detection/Wait times.
- [ ] **Venue lighting:** repeat independent movement and stillness under the
  actual demo lighting. Also try dimmer light and a bright background. Record
  which conditions cause blur, low FPS, or lost palms.
- [ ] **Distance/reach:** try expected player distances and comfortable high/low
  positions. Note the usable area; reach calibration is not yet implemented.

Skipped frames are expected when capture is faster than detection. The important
check is that delay does not grow as old frames accumulate. Wait measures only
read-completion to selection for inference, excluding camera/driver buffering,
exposure, and inference. Low Wait does not prove low end-to-end latency.

## UDP and shutdown

- [ ] **Live receiver:** receiver summaries follow each player's palm and states.
  Add `--json` if you need to inspect complete packets; both slots remain present.
- [ ] **Stop sender:** quit the demo. Receiver reports NO FRESH DATA after its
  500 ms timeout, plus up to 200 ms until the next printed status.
- [ ] **Restart sender:** restart the demo without restarting the receiver.
  Fresh data resumes even though packet sequence numbers restart at zero.
- [ ] **Close/reopen:** quit with Q/Esc, then relaunch three times. The webcam
  should open each time, without a previous process retaining it.
- [ ] **Optional external-camera disconnect:** unplug a USB webcam while running.
  Expect a read error or a 2-second no-frame timeout; the receiver must time out.
  A driver blocked in native read may produce the documented shutdown warning.
  Reconnect and relaunch to recover; automatic reconnection is not implemented.

## Gestures

After downloading the gesture model with `python vision/download_model.py --gestures`,
run `python vision/vertical_demo.py --debug --gestures` in an activated venv
(or prefix with `uv run`). Gesture labels appear on the cursor panel and debug
image. Use only one player initially. These live tests have not been marked as passed.

For the palm/thumbs-up/pinch retest, use `python vision/vertical_demo.py --debug --gesture-debug`
in an activated venv, or prefix with `uv run`. Green rings identify the estimated
thumb/index tips; amber rings mark the other three fingertips. Terminal output
includes `model`, `gap`, `gap3d`, `extended`, `curled`, `index_reach`, `thumb_reach`,
`palm_clearance`, `finger_clearance`, `approach_angle`, `thumb_tilt`, `pinch_shape`,
`thumb_allowed`, `pinch_block`, `raw`, and
`final` for each assigned hand; `hand missing` identifies tracking loss.
Record a few diagnostic lines for each failed pose. No new model download is needed.
Open-palm diagnostics include `min_tip_gap`, `closest_tips`, and `open_block`.
Tip landmark IDs are thumb=4, index=8, middle=12, ring=16, little=20. The thumb/index
gap must be at least 0.55 of palm size and every pair at least 0.18. If touching
fingers have a large reported gap, inspect the fingertip markers for tracking error.

- [ ] **Normal palm:** hold an open palm for 2 seconds with each hand. It reads
  OPEN_PALM. Moving your fingers naturally should not repeatedly trigger FIST/PINCH.
- [ ] **Open hand with touching tips:** keep the other three fingers extended and
  touch thumb/index tips. The pose should become UNKNOWN within 100 ms of its last
  OPEN_PALM support, even with a strong model Open_Palm label. Expect
  `open_block=thumb_index_gap` (possibly also `finger_separation`). Separate the
  fingers again and confirm OPEN_PALM returns on both hands.
- [ ] **Other finger contact:** bring middle/ring or ring/little fingertips
  together while keeping the hand open. Expect `open_block=finger_separation` and
  UNKNOWN after stabilization; spread all five fingers again to restore OPEN_PALM.
- [ ] **Intended fist:** close your fist with the knuckles and thumb facing the
  camera, as intended for gameplay. Hold 2 seconds on each hand. It reads FIST,
  clearly distinct from OPEN_PALM. Record failure angles and distances.
- [ ] **Moderate-confidence fist:** repeat the right-hand poses that produced
  `model=Closed_Fist:0.57` and `0.61`. With no extended fingers and compact curled
  geometry, expect `fist_support=1` and FIST after confirmation. Repeat with the
  left hand and vary the curl slightly. This supported path needs a model score
  of at least 0.55; without shape support the cutoff remains 0.70. A model None
  prediction still stays UNKNOWN unless another gesture has sufficient evidence.
- [ ] **Fist orientation:** rotate the fist toward each side and back. Current
  FIST is general closed-fist detection, not an enforced facing direction; note
  which orientations it accepts before deciding whether orientation gating is needed.
- [ ] **Thumbs-up:** curl four fingers and point the thumb upward. Each hand
  reads THUMBS_UP instead of FIST, PINCH, or OPEN_PALM.
- [ ] **Thumb direction tolerance:** keep the camera level. Hold the thumb straight
  up, then tilt it to each side. THUMBS_UP requires `thumb_tilt` at most 25 degrees;
  a larger tilt should clear it within 100 ms even if `model=Thumb_Up` stays strong.
  Repeat for both hands and try bending just the tip sideways.
- [ ] **Natural thumbs-up stability:** repeat the intended thumbs-up that measured
  0.8-21.2 degrees. Once confirmed, hold it for two seconds while moving naturally.
  It should stay THUMBS_UP on both hands. This tolerance also accepts the earlier
  7.7-degree tilted pose; the current angle metric cannot distinguish that pose
  from the intended examples. `pinch_block` failures are expected here; check
  `thumb_allowed=1` instead.
- [ ] **Touching fist facing camera:** hold the reported fist with index/thumb
  touching and pointing at the lens. It must not read THUMBS_UP even if the thumb
  looks vertical in the image. `thumb_allowed=0` when `gap` is below 0.55.
  If the model reports None, UNKNOWN is expected rather than a forced FIST label.
- [ ] **Closed-hand pinch:** loosely curl middle, ring, and little fingers,
  then reach the index and thumb away from the palm and other fingers until
  their tips touch.
  Each hand reads PINCH with `curled=3/3`. Repeat at near/far comfortable distances
  ten times.
- [ ] **Loose pinch:** keep thumb/index touching and gradually uncurl the other
  three fingers so their tips sit farther from the palm while their joints remain
  bent. Each hand should retain PINCH and `curled=3/3`; fingertips no longer need
  to tuck near the palm. Fully straightening a supporting finger should clear PINCH.
- [ ] **Open-hand pinch rejection:** touch thumb/index tips with the other three
  fingers extended (an OK sign). Neither hand should read PINCH. Starting from a
  valid closed-hand pinch, extend each supporting finger separately; PINCH should
  clear within 100 ms of losing shape support.
- [ ] **Pinch release:** separate the index/thumb tips and return to open palm.
  PINCH clears. It may briefly read UNKNOWN during the change.
- [ ] **Fist versus pinch:** alternate these poses ten times; a fully clenched
  fist should not produce PINCH merely because its fingertips are close together.
- [ ] **Raised-index fist:** place the thumb over the index in a fist, then raise
  the index slightly while maintaining contact. Repeat with both hands, at
  different camera distances and wrist angles. It should remain FIST when the
  model recognizes it, or UNKNOWN when uncertain, rather than PINCH. Then reach
  both tips farther away from the palm and other fingers to make a deliberate
  pinch. Record `palm_clearance`, `thumb_reach`, and `finger_clearance` on failures.
- [ ] **Looser-index fist:** start with the left fist, thumb over index, and
  gradually reduce the index bend; repeat on the right. Overlapping fingers
  should not become PINCH merely by reaching farther out. Then form a deliberate
  pinch with the two touching fingertips reaching clear of the rest of the hand.
  Record `model`, `raw`, `final`, and `pinch_block` for both poses if confusion remains.
- [ ] **Reported pinch retest:** repeat the right-hand pinch that measured
  `gap=0.13` and `approach_angle=102-104`. Angle is no longer a gate; if PINCH is still
  missing, record the complete line including `pinch_shape` (reach/curl/depth
  checks). Test the left hand too. A passing angle alone does not confirm pinch.
- [ ] **Loose-fist sequence:** repeat the right-hand fist while relaxing the index.
  The reported `index_reach=0.42-0.70` and `palm_clearance=0.41-0.48` samples should
  fail pinch reach checks. Confirm FIST when the model is confident, or UNKNOWN
  when uncertain. Hold each pose long enough for stabilization to settle.
- [ ] **Low-angle good pinches:** repeat the good right/left pinches with approach
  angles around 59, 89, and 94 degrees. With sufficient reach/clearance and touching
  tips, each should produce PINCH. `pinch_block` should be `none`.
- [ ] **Independent gestures:** left FIST with right OPEN_PALM, then swap; repeat
  with THUMBS_UP and PINCH. Labels must stay with the correct slot.
- [ ] **Loss/reset:** hide a gesturing hand. Its gesture immediately becomes
  UNKNOWN, including while its cursor position is COASTING. Reappear and hold
  a different gesture: the new label confirms after about 40 ms of supporting observations.
- [ ] **Score dips:** while a hand stays TRACKED, a brief uncertain classification
  should not flicker the gesture. An unsupported pose should clear the previous
  gesture within 100 ms of its last support. This grace period does not apply
  when the hand itself disappears.
- [ ] **UDP:** receiver with `--json` shows gesture and gesture_conf on each hand.
  UNKNOWN carries zero gesture_conf. Stop gesture mode and run plain mode:
  packets return to the original fields without gesture data.

The pinch score primarily describes image-space tip proximity with shape/depth
checks; it cannot prove skin contact. All three supporting fingers must be at
least loosely curled; their tips do not need to reach the palm,
and both touching tips must stay clear of the palm and the other fingers.
`index_reach` must be at least 0.75, `palm_clearance` at least 0.60,
`thumb_reach` at least 0.55, and `finger_clearance` at least 0.50 (all relative to
palm size). `approach_angle` is diagnostic only. All pinch shape checks
apply both when entering and holding a pinch; short stabilization still applies.
New pinch entry requires a gap at most 0.30
of palm size; the 0.30-0.45 band only retains an existing pinch to reduce flicker.
Record false positives/negatives before treating these as reliable game controls.

## Results

Date / camera / player distance / lighting:

| Measurement | Start | After 3 minutes |
|---|---|---|
| Capture FPS | | |
| Loop FPS | | |
| Detection ms | | |
| Wait ms | | |
| Skipped total | | |

| Failed test | Steps to reproduce | Observed result | Expected result |
|---|---|---|---|
| Bystander right hand | Hide player's left; bystander shows right | Left cursor can follow bystander (reported) | Left remains unavailable |
| | | | |
