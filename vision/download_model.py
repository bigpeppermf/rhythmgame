"""Download Google's Hand Landmarker model once; inference stays local."""

from pathlib import Path
import shutil
import sys
from urllib.request import urlopen

MODEL_URL = (
    "https://storage.googleapis.com/mediapipe-models/hand_landmarker/"
    "hand_landmarker/float16/1/hand_landmarker.task"
)
MODEL_PATH = Path(__file__).parent / "models" / "hand_landmarker.task"


def main():
    if MODEL_PATH.is_file():
        print(f"Model already present: {MODEL_PATH}")
        return
    MODEL_PATH.parent.mkdir(parents=True, exist_ok=True)
    temporary = MODEL_PATH.with_suffix(".download")
    try:
        with urlopen(MODEL_URL, timeout=60) as source, temporary.open("wb") as target:
            shutil.copyfileobj(source, target)
        temporary.replace(MODEL_PATH)
    finally:
        temporary.unlink(missing_ok=True)
    print(f"Downloaded model: {MODEL_PATH}")


if __name__ == "__main__":
    try:
        main()
    except OSError as error:
        print(f"Model download failed: {error}", file=sys.stderr)
        sys.exit(1)
