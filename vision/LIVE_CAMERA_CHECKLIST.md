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
