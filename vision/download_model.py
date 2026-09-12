"""Download Google's Hand Landmarker model once; inference stays local."""

from pathlib import Path
import argparse
import shutil
import sys
from urllib.request import urlopen

MODEL_URL = (
    "https://storage.googleapis.com/mediapipe-models/hand_landmarker/"
    "hand_landmarker/float16/1/hand_landmarker.task"
)
MODEL_PATH = Path(__file__).parent / "models" / "hand_landmarker.task"
GESTURE_MODEL_URL = (
    "https://storage.googleapis.com/mediapipe-models/gesture_recognizer/"
    "gesture_recognizer/float16/1/gesture_recognizer.task"
)
GESTURE_MODEL_PATH = MODEL_PATH.with_name("gesture_recognizer.task")


def download_model(url, path):
    if path.is_file():
        print(f"Model already present: {path}")
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".download")
    try:
        with urlopen(url, timeout=60) as source, temporary.open("wb") as target:
            shutil.copyfileobj(source, target)
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)
    print(f"Downloaded model: {path}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--gestures", action="store_true", help="Also download the gesture model")
    args = parser.parse_args()
    download_model(MODEL_URL, MODEL_PATH)
    if args.gestures:
        download_model(GESTURE_MODEL_URL, GESTURE_MODEL_PATH)


if __name__ == "__main__":
    try:
        main()
    except OSError as error:
        print(f"Model download failed: {error}", file=sys.stderr)
        sys.exit(1)
