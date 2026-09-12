# Live camera checklist

Check a box only after observing the expected result. Leave failures unchecked
and record what happened below. These are manual acceptance tests; automated
tests do not establish live tracking accuracy or latency.

## Setup

From `rhythmgame`, start the demo with the camera debug window:

```powershell
.\.venv\Scripts\python.exe vision/vertical_demo.py --debug
```

For UDP tests, start a second terminal in the same directory:

```powershell
.\.venv\Scripts\python.exe vision/udp_receiver.py
```

Use **D** to toggle debug, **Q/Esc** in an OpenCV window to quit the demo,
and **Ctrl+C** in the receiver terminal to stop the receiver. Capture threading
is automatic for a live webcam. Start with only the player visible and allow
5 seconds for startup and FPS measurements before judging performance.

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

## Other people / player ownership — known failing area

The current tracker has no selected-player identity. These tests describe the
desired behavior and are expected to expose failures until ownership is added.
Debug hand labels currently show the assigned slot, not the raw model label.

- [ ] **Bystander right hand:** establish both player hands, then hide the player's
  left while a bystander shows their right near its previous position. Desired:
  player's left becomes LOST; bystander never controls it. **User-reported failure.**
- [ ] **Bystander same-side hand:** hide the player's left, wait 1 second, then
  show a bystander's left. Desired: still LOST. This checks ownership separately
  from whether left/right classification is correct. Repeat for the right slot.
- [ ] **Background movement:** keep both player hands visible while a bystander
  waves from each side and behind the player. Desired: no cursor takeover.
- [ ] **Player leaves:** player exits while a bystander remains. Desired: both
  hands LOST until the player is explicitly selected again, not automatic takeover.

Why this can happen now: `PalmSlots` uses nearest position within its 200 ms
continuity window, ignoring handedness in that window. After expiry it uses
handedness again, which still does not identify the owner. `num_hands=2` limits
the number of detections; it does not guarantee two hands from the same person.

Potential next implementation: explicitly select the player's body, preserve
that body track, associate palm wrist landmarks with that body's left/right
wrists, and reject ambiguous matches. When the body track is lost, require
reselection rather than taking another visible person. This is proposed work,
not functionality provided by the current detector. A cropped player area can
reduce background interference but cannot reject an intruding hand on its own.

MediaPipe Pose Landmarker supplies body landmarks including left/right shoulders,
elbows, and wrists; player selection and association logic must be built around
them. [Official model guide](https://ai.google.dev/edge/mediapipe/solutions/vision/pose_landmarker).

## Capture performance and room conditions

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
includes `model`, `gap`, `gap3d`, `extended`, `curled`, `index_reach`, `raw`, and
`final` for each assigned hand; `hand missing` identifies tracking loss.
Record a few diagnostic lines for each failed pose. No new model download is needed.

- [ ] **Normal palm:** hold an open palm for 2 seconds with each hand. It reads
  OPEN_PALM. Moving your fingers naturally should not repeatedly trigger FIST/PINCH.
- [ ] **Intended fist:** close your fist with the knuckles and thumb facing the
  camera, as intended for gameplay. Hold 2 seconds on each hand. It reads FIST,
  clearly distinct from OPEN_PALM. Record failure angles and distances.
- [ ] **Fist orientation:** rotate the fist toward each side and back. Current
  FIST is general closed-fist detection, not an enforced facing direction; note
  which orientations it accepts before deciding whether orientation gating is needed.
- [ ] **Thumbs-up:** curl four fingers and point the thumb upward. Each hand
  reads THUMBS_UP instead of FIST, PINCH, or OPEN_PALM.
- [ ] **Closed-hand pinch:** curl middle, ring, and little fingers into the palm,
  then reach the index fingertip toward the thumb tip until they touch.
  Each hand reads PINCH with `curled=3/3`. Repeat at near/far comfortable distances
  ten times.
- [ ] **Open-hand pinch rejection:** touch thumb/index tips with the other three
  fingers extended (an OK sign). Neither hand should read PINCH. Starting from a
  valid closed-hand pinch, extend each supporting finger separately; PINCH should
  clear within 100 ms of losing shape support.
- [ ] **Pinch release:** separate the index/thumb tips and return to open palm.
  PINCH clears. It may briefly read UNKNOWN during the change.
- [ ] **Fist versus pinch:** alternate these poses ten times; a fully clenched
  fist should not produce PINCH merely because its fingertips are close together.
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
checks; it cannot prove skin contact. All three supporting fingers must be curled,
and the index must reach away from its knuckle instead of tucking into a fist.
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
