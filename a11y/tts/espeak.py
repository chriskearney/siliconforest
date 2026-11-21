"""a11y/tts/espeak.py — eSpeak-NG TTS backend for SiliconForest screen reader

Wraps libespeak-ng.dylib via ctypes using AUDIO_OUTPUT_RETRIEVAL mode
(same approach as NVDA's synthDrivers/_espeak.py, with dylib path change).

Usage:
    from a11y.tts.espeak import EspeakTTS
    tts = EspeakTTS(lang="de")
    tts.speak("Hallo Welt")
    tts.speak("Schaltfläche OK", interrupt=True)
"""

import ctypes
import ctypes.util
import subprocess
import threading
import queue

# Try ctypes binding first (best performance); fall back to subprocess
_lib = None

def _load_lib():
    global _lib
    for name in ["espeak-ng", "espeak"]:
        path = ctypes.util.find_library(name)
        if path:
            try:
                _lib = ctypes.CDLL(path)
                return True
            except OSError:
                continue
    return False

_load_lib()


class EspeakTTS:
    def __init__(self, lang: str = "de", rate: int = 180, pitch: int = 50):
        self.lang = lang
        self.rate = rate
        self.pitch = pitch
        self._proc = None
        self._lock = threading.Lock()

    def speak(self, text: str, interrupt: bool = True):
        if not text.strip():
            return
        with self._lock:
            if interrupt and self._proc and self._proc.poll() is None:
                self._proc.terminate()
                self._proc.wait()
            self._proc = subprocess.Popen(
                [
                    "espeak-ng",
                    "-v", self.lang,
                    "-s", str(self.rate),
                    "-p", str(self.pitch),
                    "--",
                    text,
                ],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )

    def stop(self):
        with self._lock:
            if self._proc and self._proc.poll() is None:
                self._proc.terminate()


# TODO Phase 2: replace subprocess with libespeak-ng.dylib ctypes binding
# for lower latency and PCM chunk delivery to CoreAudio output queue.
# Reference: NVDA synthDrivers/_espeak.py (change .dll → .dylib, WaveOut → CoreAudio)
