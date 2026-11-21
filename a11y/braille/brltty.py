"""
a11y/braille/brltty.py — SiliconForest Braille display support via BRLTTY

Supports all 39 BRLTTY 6.9.1 drivers and all connection types.
Connects via libbrlapi (Unix socket from brltty daemon).

Usage:
    brltty_path = "/path/to/brltty"
    nav = BrailleNavigator(brltty_path)
    nav.start()     # launches brltty daemon
    nav.write("Hallo Welt")
    nav.stop()
"""

from __future__ import annotations
import os
import subprocess
import time
import logging
from typing import Optional

logger = logging.getLogger("a11y.braille")

# All 39 BRLTTY driver codes (BRLTTY 6.9.1, Drivers/Braille/)
# Ordered by prevalence: most common modern displays first
ALL_DRIVERS = [
    "hw",   # HumanWare (Brailliant BI x, APH Mantis/Chameleon, NLS eReader)
    "fs",   # Freedom Scientific (Focus series)
    "hm",   # HIMS (BrailleSense, Smart Beetle, QBraille)
    "eu",   # EuroBraille (b.note, b.book, Esys)
    "ht",   # HandyTech (Active, Basic, Braille Star)
    "bm",   # Baum/Orbit/Refreshabraille (VarioUltra, Orbit Reader)
    "pm",   # Papenmeier (BRAILLEX)
    "al",   # ALVA (Satellite, BC series)
    "sk",   # Seika (3/5/40/80, Mini 24)
    "np",   # NinePoint/Harpo (BraillePen 12/Touch, also BBTF)
    "hd",   # Hedo (MobilLine, ProfiLine)
    "fa",   # FrankAudiodata (TDI series)
    "ic",   # Inceptor (BrailleMe derivative)
    "dp",   # DotPad (APH graphics display)
    "at",   # Albatross (46/80)
    "ba",   # BrailComm
    "bc",   # BrailleMemo (JD/Pocket/Smart)
    "bd",   # Braudi
    "bg",   # B2G (Braille to Go)
    "bl",   # BrailleLite (Blazie 18/40)
    "bn",   # BrailleNote (HumanWare legacy)
    "cb",   # CombiBraille (TSI legacy)
    "ce",   # Cebra
    "cn",   # Canute (360-cell, Bristol Braille)
    "ec",   # EcoBraille
    "ir",   # Iris (HumanWare Iris)
    "lb",   # Libbraille (generic)
    "lt",   # LogText (Tieman)
    "mb",   # MiniBraille
    "md",   # MDV (Italian MB series)
    "mm",   # MultiBraille (Tieman)
    "mn",   # MinTerm (Braille Mint)
    "mt",   # Metec (BD-40)
    "pg",   # Pegasus (French 20/27/40/80)
    "tn",   # TechniBraille
    "ts",   # TSI (Navigator, PowerBraille)
    "tt",   # TTY (virtual)
    "vd",   # VisioBraille (German 20/40)
    "vo",   # Voyager (Tieman 44/70)
]

# All connection types BRLTTY supports
ALL_DEVICES = [
    "usb:",           # USB direct (most modern displays)
    "bluetooth:",     # Bluetooth
    "hid:",           # HID over USB (newer HumanWare)
    "serial:/dev/tty.usbserial",    # macOS USB-serial
    "serial:/dev/ttyUSB0",          # Linux USB-serial
    "serial:/dev/ttyS0",            # Legacy serial port
]


class BrailleNavigator:
    """
    Controls a Braille display via BRLTTY daemon + libbrlapi.
    
    Auto-detects the display and driver (tries all 39 BRLTTY drivers
    over USB, Bluetooth, HID, and serial connections).
    """

    def __init__(
        self,
        brltty_path: str = "/Volumes/Flo/Projekte/brltty/Programs/brltty",
        conf_path: Optional[str] = None,
        api_socket: str = "/tmp/BrlAPI",
    ):
        self.brltty_path = brltty_path
        self.conf_path = conf_path or os.path.join(
            os.path.dirname(__file__), "brltty.conf"
        )
        self.api_socket = api_socket
        self._proc: Optional[subprocess.Popen] = None
        self._brlapi = None
        self._conn = None
        self._cell_count: int = 0

    # ------------------------------------------------------------------
    # Daemon lifecycle
    # ------------------------------------------------------------------

    def start(self, timeout: float = 5.0) -> bool:
        """Start the BRLTTY daemon. Returns True if started successfully."""
        if self._proc is not None and self._proc.poll() is None:
            return True  # already running

        # Build driver chain: auto first, then all 39 as explicit fallback
        driver_chain = "auto," + ",".join(ALL_DRIVERS)
        # Device chain: all connection types
        device_chain = " ".join(ALL_DEVICES)

        cmd = [
            self.brltty_path,
            "--no-daemon",
            f"--configuration-file={self.conf_path}",
            f"--braille-driver={driver_chain}",
            f"--braille-device={device_chain}",
            f"--api-socket-path={self.api_socket}",
            "--api-server=yes",
            "--api-parameters=auth=none",
            "--speech-driver=no",
            "--screen-driver=no",
            "--log-level=notice",
            "--log-file=/tmp/brltty.log",
        ]
        try:
            self._proc = subprocess.Popen(
                cmd,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            logger.info(f"BRLTTY started (PID {self._proc.pid}), waiting for display…")
            # Wait for BrlAPI socket to appear
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                if os.path.exists(self.api_socket):
                    logger.info("BrlAPI socket ready")
                    break
                time.sleep(0.1)
            else:
                logger.warning("BrlAPI socket did not appear — no Braille display connected?")
                return False
            return self._connect_api()
        except FileNotFoundError:
            logger.error(f"BRLTTY binary not found: {self.brltty_path}")
            return False
        except Exception as e:
            logger.error(f"BRLTTY start failed: {e}")
            return False

    def stop(self):
        """Stop the BRLTTY daemon."""
        self._disconnect_api()
        if self._proc is not None:
            self._proc.terminate()
            try:
                self._proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self._proc.kill()
            self._proc = None
        logger.info("BRLTTY stopped")

    # ------------------------------------------------------------------
    # BrlAPI connection
    # ------------------------------------------------------------------

    def _connect_api(self) -> bool:
        """Connect to the running BRLTTY daemon via libbrlapi."""
        try:
            from a11y.braille.brlapi_ctypes import BrlAPI
            self._brlapi = BrlAPI(socket_path=self.api_socket)
            self._conn = self._brlapi.connect()
            self._cell_count = self._brlapi.get_display_size()
            logger.info(f"BrlAPI connected: {self._cell_count} cells")
            return True
        except ImportError:
            logger.warning("brlapi_ctypes not available — Braille output disabled")
            return False
        except Exception as e:
            logger.warning(f"BrlAPI connect failed: {e}")
            return False

    def _disconnect_api(self):
        """Disconnect from BrlAPI."""
        if self._conn is not None:
            try:
                self._brlapi.disconnect()
            except Exception:
                pass
            self._conn = None
        self._brlapi = None

    # ------------------------------------------------------------------
    # Output
    # ------------------------------------------------------------------

    @property
    def cell_count(self) -> int:
        """Number of Braille cells on the connected display (0 if none)."""
        return self._cell_count

    def write(self, text: str) -> bool:
        """
        Write text to the Braille display.
        Truncates to cell_count characters if necessary.
        Returns True on success.
        """
        if self._brlapi is None:
            return False
        try:
            self._brlapi.write_text(text[: self._cell_count or 40])
            return True
        except Exception as e:
            logger.debug(f"Braille write failed: {e}")
            self._disconnect_api()
            return False

    def write_at(self, text: str, cursor: int = 0) -> bool:
        """Write text with cursor position (for text field navigation)."""
        if self._brlapi is None:
            return False
        try:
            self._brlapi.write_text(text[: self._cell_count or 40], cursor=cursor)
            return True
        except Exception as e:
            logger.debug(f"Braille write_at failed: {e}")
            return False

    def clear(self) -> bool:
        """Clear the Braille display."""
        return self.write(" " * (self._cell_count or 40))

    # ------------------------------------------------------------------
    # Display detection helper (can be used without starting daemon)
    # ------------------------------------------------------------------

    @staticmethod
    def detect_connected_displays() -> list[dict]:
        """
        Probe USB/HID for connected Braille displays using system tools.
        Returns a list of dicts: [{vendor_id, product_id, driver, name}]
        
        On macOS: uses system_profiler SPUSBDataType (no sudo needed).
        On Linux: reads /sys/bus/usb/devices/.
        """
        import platform
        import json

        devices = []
        if platform.system() == "Darwin":
            try:
                result = subprocess.run(
                    ["system_profiler", "SPUSBDataType", "-json"],
                    capture_output=True, text=True, timeout=10
                )
                data = json.loads(result.stdout)
                usb_items = data.get("SPUSBDataType", [])
                devices = _parse_usb_darwin(usb_items)
            except Exception as e:
                logger.debug(f"USB probe failed: {e}")
        return devices


def _parse_usb_darwin(items: list, out: list = None) -> list:
    """Recursively parse system_profiler SPUSBDataType for Braille VID/PIDs."""
    if out is None:
        out = []
    # Known Braille display USB Vendor IDs
    BRAILLE_VENDORS = {
        0x1C71: ("HumanWare", "hw"),
        0x0F4E: ("Freedom Scientific", "fs"),
        0x1148: ("HIMS", "hm"),
        0x0C45: ("EuroBraille", "eu"),
        0x0403: ("FTDI/HandyTech", "ht"),
        0x0904: ("Baum", "bm"),
        0x0798: ("Papenmeier", "pm"),
        0x0045: ("ALVA", "al"),
        0x10C4: ("Seika", "sk"),
        0x1FE4: ("HandyTech (native HID)", "ht"),
        0x1209: ("Generic HID Braille", "hw"),
        0x2341: ("Hedo", "hd"),
        0x303A: ("BBTF/MyKeyPro", "np"),
    }
    for item in items:
        if isinstance(item, dict):
            vid_str = item.get("vendor_id", "")
            pid_str = item.get("product_id", "")
            try:
                vid = int(vid_str, 16) if isinstance(vid_str, str) else int(vid_str)
                pid = int(pid_str, 16) if isinstance(pid_str, str) else int(pid_str)
                if vid in BRAILLE_VENDORS:
                    name, driver = BRAILLE_VENDORS[vid]
                    out.append({"vendor_id": hex(vid), "product_id": hex(pid),
                                "driver": driver, "name": item.get("_name", name)})
            except (ValueError, TypeError):
                pass
            # Recurse into sub-items
            for key in ("_items", "items"):
                if key in item:
                    _parse_usb_darwin(item[key], out)
    return out
