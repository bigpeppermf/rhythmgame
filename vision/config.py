"""One place for every tunable. Nothing else hardcodes a number."""

CAMERA = {
    "index": 0,
    # Low resolution on purpose. You are extracting ONE NUMBER, not a photo.
    # Lower res means faster capture, less processing, and less motion blur.
    "width": 640,
    "height": 480,
    "fps": 60,
    "fourcc": "MJPG",
    "exposure": None,   # set an int to lock it; None leaves autoexposure on
}

FILTER = {
    "min_cutoff": 1.0,   # lower = less resting jitter, more lag
    "beta": 0.007,       # higher = less lag when moving fast
}

EMIT = {"host": "127.0.0.1", "port": 9000}

# Calibrated play area in normalized *camera* coordinates, written by the
# calibration step. Map ~85% of the player's measured reach to the full play
# area, not 100% - demanding maximum extension every time causes fatigue
# within one song.
CALIBRATION_FILE = "calibration.local.json"
REACH_USAGE = 0.85
