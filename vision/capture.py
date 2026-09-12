"""Threaded camera capture.

This module exists because of one bug that costs more latency than every
algorithm choice combined: cv2.VideoCapture queues frames internally. If your
processing loop is even slightly slower than the camera's frame rate, you fall
behind the queue and stay behind - permanently. You end up decoding a frame
captured 4 frames ago, which at 30fps is 130ms of latency you added for free,
and nothing in your code looks wrong.

The fix is to read continuously on a dedicated thread that overwrites a single
"latest frame" slot. The main loop always gets the newest frame and never
inherits a backlog. Frames that arrive while the main loop is busy are simply
dropped, which is correct: a stale frame is better than a late one.
"""
import threading
import time

import cv2


class Camera:
    def __init__(self, index=0, width=640, height=480, fps=60, fourcc="MJPG",
                 exposure=None, backend=cv2.CAP_V4L2):
        self.cap = cv2.VideoCapture(index, backend)
        if not self.cap.isOpened():
            raise RuntimeError(f"could not open camera {index}")

        # MJPG first: the default YUYV format saturates USB bandwidth and often
        # caps the camera at 30fps (or worse at higher resolutions). This single
        # line is frequently the difference between 30 and 60fps.
        self.cap.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*fourcc))
        self.cap.set(cv2.CAP_PROP_FRAME_WIDTH, width)
        self.cap.set(cv2.CAP_PROP_FRAME_HEIGHT, height)
        self.cap.set(cv2.CAP_PROP_FPS, fps)
        self.cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)

        if exposure is not None:
            # Autoexposure is a latency AND blur amplifier: in dim light it
            # lengthens exposure time, which both slows frame delivery and
            # smears a fast-moving hand into something untrackable.
            self.cap.set(cv2.CAP_PROP_AUTO_EXPOSURE, 0.25)  # V4L2 manual mode
            self.cap.set(cv2.CAP_PROP_EXPOSURE, exposure)

        self._frame = None
        self._t_capture = 0.0
        self._seq = 0
        self._lock = threading.Lock()
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._loop, daemon=True)
        self._thread.start()

    def _loop(self):
        while not self._stop.is_set():
            ok, frame = self.cap.read()
            # Stamp at capture, never at send. Stamping later folds all of your
            # processing variance into the number and makes it useless for
            # jitter measurement downstream.
            t = time.perf_counter()
            if not ok:
                time.sleep(0.005)
                continue
            with self._lock:
                self._frame = frame
                self._t_capture = t
                self._seq += 1

    def read(self):
        """Newest frame as (seq, t_capture, frame), or (0, 0.0, None)."""
        with self._lock:
            if self._frame is None:
                return 0, 0.0, None
            return self._seq, self._t_capture, self._frame

    def settings(self):
        """What the camera actually accepted. Drivers silently refuse requests,
        so always read back rather than trusting your set() calls."""
        g = self.cap.get
        cc = int(g(cv2.CAP_PROP_FOURCC))
        return {
            "width": int(g(cv2.CAP_PROP_FRAME_WIDTH)),
            "height": int(g(cv2.CAP_PROP_FRAME_HEIGHT)),
            "fps_reported": g(cv2.CAP_PROP_FPS),
            "fourcc": "".join(chr((cc >> 8 * i) & 0xFF) for i in range(4)),
            "exposure": g(cv2.CAP_PROP_EXPOSURE),
            "auto_exposure": g(cv2.CAP_PROP_AUTO_EXPOSURE),
        }

    def close(self):
        self._stop.set()
        self._thread.join(timeout=1.0)
        self.cap.release()
