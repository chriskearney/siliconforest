"""brlapi_ctypes.py — Minimal BrlAPI ctypes wrapper for SiliconForest

A lightweight alternative to the Cython-based brlapi module.
Uses ctypes to call libbrlapi.dylib directly.
Works with any BRLTTY version that provides libbrlapi.

Install:
  Copy to your Python path alongside libbrlapi.dylib.
  Or set DYLD_LIBRARY_PATH to the directory containing libbrlapi.dylib.

Brailliant BI 40X: VID 0x1C71 PID 0xC131, hw driver, HID protocol.
Start BRLTTY before importing:
  brltty -b hw -d usb: -A auth=none &
"""

import ctypes
import ctypes.util
import os

# Try to find libbrlapi
_lib_paths = [
    # SiliconForest build
    "/Volumes/Flo/Projekte/brltty/Programs/libbrlapi.dylib",
    # System install
    "/usr/local/lib/libbrlapi.dylib",
    "/opt/homebrew/lib/libbrlapi.dylib",
    # Auto-detect
    ctypes.util.find_library("brlapi") or "",
]

_lib = None
for _path in _lib_paths:
    if _path and os.path.exists(_path):
        try:
            _lib = ctypes.CDLL(_path)
            break
        except OSError:
            continue

if _lib is None:
    raise ImportError(
        "libbrlapi.dylib not found. "
        "Build BRLTTY: cd /Volumes/Flo/Projekte/brltty && make -C Programs libbrlapi.dylib"
    )

# --- C types ---
brlapi_handle_t = ctypes.c_void_p
brlapi_connectionSettings_t = ctypes.c_char_p * 2  # simplified

class ConnectionSettings(ctypes.Structure):
    _fields_ = [
        ("auth", ctypes.c_char_p),
        ("host", ctypes.c_char_p),
    ]

class DisplaySize(ctypes.Structure):
    _fields_ = [
        ("x", ctypes.c_uint32),
        ("y", ctypes.c_uint32),
    ]

# --- API bindings ---
_lib.brlapi_openConnection.restype = ctypes.c_int
_lib.brlapi_openConnection.argtypes = [ctypes.POINTER(ConnectionSettings), ctypes.c_void_p]

_lib.brlapi_closeConnection.restype = None
_lib.brlapi_closeConnection.argtypes = []

_lib.brlapi_getDisplaySize.restype = ctypes.c_int
_lib.brlapi_getDisplaySize.argtypes = [ctypes.POINTER(DisplaySize)]

_lib.brlapi_writeText.restype = ctypes.c_int
_lib.brlapi_writeText.argtypes = [ctypes.c_int, ctypes.c_char_p]

_lib.brlapi_enterTtyMode.restype = ctypes.c_int
_lib.brlapi_enterTtyMode.argtypes = [ctypes.c_int, ctypes.c_char_p]

_lib.brlapi_leaveTtyMode.restype = ctypes.c_int
_lib.brlapi_leaveTtyMode.argtypes = []

_lib.brlapi_readKey.restype = ctypes.c_int
_lib.brlapi_readKey.argtypes = [ctypes.c_int, ctypes.POINTER(ctypes.c_uint64)]

# Error constants
CURSOR_OFF = -1

class ConnectionError(Exception):
    pass


class Connection:
    """Simplified BrlAPI connection."""

    def __init__(self, host: str = "localhost", auth: str = ""):
        settings = ConnectionSettings()
        settings.host = host.encode() if host else None
        settings.auth = auth.encode() if auth else None
        result = _lib.brlapi_openConnection(ctypes.byref(settings), None)
        if result < 0:
            raise ConnectionError("Could not connect to BRLTTY. Is brltty running?")
        self._connected = True

    @property
    def displaySize(self) -> tuple[int, int]:
        size = DisplaySize()
        if _lib.brlapi_getDisplaySize(ctypes.byref(size)) < 0:
            return (0, 0)
        return (size.x, size.y)

    def enterTtyMode(self, tty: int = 0, driver: str = ""):
        result = _lib.brlapi_enterTtyMode(tty, driver.encode() if driver else None)
        if result < 0:
            raise ConnectionError("enterTtyMode failed")

    def leaveRawMode(self):
        _lib.brlapi_leaveTtyMode()

    def writeText(self, cursor: int, text: str):
        encoded = text.encode("UTF-8", errors="replace")
        result = _lib.brlapi_writeText(cursor, encoded)
        if result < 0:
            raise ConnectionError("writeText failed")

    def readKey(self, block: bool = False) -> int | None:
        key = ctypes.c_uint64(0)
        result = _lib.brlapi_readKey(1 if block else 0, ctypes.byref(key))
        if result <= 0:
            return None
        return key.value

    def close(self):
        if self._connected:
            _lib.brlapi_closeConnection()
            self._connected = False

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()


def test_connection():
    """Quick test: connect to BRLTTY and show display size."""
    try:
        conn = Connection(auth="none")
        w, h = conn.displaySize
        print(f"BrlAPI connected: {w}x{h} cells")
        conn.enterTtyMode()
        conn.writeText(CURSOR_OFF, f"SiliconForest {w} cells")
        conn.leaveRawMode()
        conn.close()
        return True
    except ConnectionError as e:
        print(f"BrlAPI test failed: {e}")
        return False


if __name__ == "__main__":
    test_connection()
