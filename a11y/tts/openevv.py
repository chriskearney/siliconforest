"""a11y/tts/openevv.py - OpenEVV (Eloquence) TTS backend for SiliconForest

Priority: OpenEVV libevv.dylib > Apple ECI libeci.dylib > eSpeak-NG fallback.
Build OpenEVV: cd /Volumes/Flo/Projekte/openevv && make
"""
import ctypes, os, subprocess, threading

_LIB_PATHS = [
    "/Volumes/Flo/Projekte/openevv/libevv.dylib",
    "/Volumes/Flo/Projekte/openevv/build/libevv.dylib",
    "/System/Library/PrivateFrameworks/TextToSpeechKonaSupport.framework/libeci.dylib",
    "/System/Library/PrivateFrameworks/TextToSpeechKonaSupport.framework/Versions/A/libeci.dylib",
]
_lib = None
for _p in _LIB_PATHS:
    if _p and os.path.exists(_p):
        try:
            _lib = ctypes.CDLL(_p)
            print(f"[openevv] {_p}")
            break
        except OSError:
            continue

class OpenEVVTTS:
    def __init__(self, lang="de", rate=180):
        self.lang, self.rate = lang, rate
        self._proc = None
        self._lock = threading.Lock()
        self._handle = None
        if _lib:
            try:
                _lib.eciNew.restype = ctypes.c_void_p
                _lib.eciAddText.restype = ctypes.c_int
                _lib.eciAddText.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
                _lib.eciSynthesize.restype = ctypes.c_int
                _lib.eciSynchronize.restype = ctypes.c_int
                _lib.eciDelete.restype = ctypes.c_int
                self._handle = _lib.eciNew()
            except Exception as e:
                print(f"[openevv] ECI init: {e}")

    @property
    def available(self):
        return bool(self._handle)

    def speak(self, text, interrupt=True):
        if not text.strip():
            return
        with self._lock:
            if interrupt and self._proc and self._proc.poll() is None:
                self._proc.terminate()
            if self.available:
                try:
                    _lib.eciAddText(self._handle, text.encode("UTF-8"))
                    _lib.eciSynthesize(self._handle)
                    _lib.eciSynchronize(self._handle)
                    return
                except Exception:
                    pass
            self._proc = subprocess.Popen(
                ["espeak-ng", "-v", self.lang, "-s", str(self.rate), "--", text],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def stop(self):
        with self._lock:
            if self._proc and self._proc.poll() is None:
                self._proc.terminate()

    def close(self):
        self.stop()
        if self._handle and _lib:
            try: _lib.eciDelete(self._handle)
            except: pass
