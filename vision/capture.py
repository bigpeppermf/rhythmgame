"""Single-slot webcam capture: replace old frames instead of queueing them."""

from dataclasses import dataclass
from threading import Condition, Event, Thread
from time import perf_counter


@dataclass(frozen=True)
class CapturedFrame:
    sequence: int
    image: object
    t_capture: float
    fps: float


class LatestFrameCapture:
    """Take ownership of an opened/configured VideoCapture and start reading.

    Only the worker calls read/release. The consumer receives a stable frame
    reference; publishing another frame never modifies one already handed out.
    """

    def __init__(self, camera):
        self._camera = camera
        self._condition = Condition()
        self._stop = Event()
        self._latest = None
        self._error = None
        self._finished = False
        # A camera driver can hang inside native read(). Do not let such a driver
        # keep the Python process alive after a bounded close/join.
        self._thread = Thread(target=self._capture, name="webcam-capture", daemon=True)
        self._thread.start()

    def _capture(self):
        sequence, count, fps = 0, 0, 0.0
        start = perf_counter()
        try:
            while not self._stop.is_set():
                ok, image = self._camera.read()
                t_capture = perf_counter()  # Immediately after read, before copying.
                if self._stop.is_set():
                    break
                if not ok:
                    raise RuntimeError("Camera stopped delivering frames.")
                sequence += 1
                count += 1
                if t_capture - start >= 1.0:
                    fps = count / (t_capture - start)
                    count, start = 0, t_capture
                frame = CapturedFrame(sequence, image.copy(), t_capture, fps)
                with self._condition:
                    self._latest = frame
                    self._condition.notify_all()
        except Exception as error:
            with self._condition:
                self._error = error
        finally:
            try:
                self._camera.release()
            finally:
                with self._condition:
                    self._finished = True
                    self._condition.notify_all()

    def get_latest(self, after_sequence=0, timeout=0.02):
        """Return a newer frame once, or None on timeout/close; propagate failure."""
        with self._condition:
            self._condition.wait_for(
                lambda: self._error is not None or self._finished or self._stop.is_set()
                or (self._latest is not None and self._latest.sequence > after_sequence),
                timeout=timeout,
            )
            if self._error is not None:
                raise RuntimeError(f"Capture failed: {self._error}") from self._error
            if self._stop.is_set() or self._finished:
                return None
            if self._latest is not None and self._latest.sequence > after_sequence:
                return self._latest
            return None

    def close(self, timeout=1.0):
        """Stop and join; False means the native driver is still stuck in read().

        Never release the camera concurrently with a native read; the worker
        releases it when read returns. Repeated close calls are safe.
        """
        self._stop.set()
        with self._condition:
            self._condition.notify_all()
        self._thread.join(timeout)
        return not self._thread.is_alive()
