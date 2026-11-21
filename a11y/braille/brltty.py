"""a11y/braille/brltty.py — BrlAPI/BRLTTY Braille integration for SiliconForest

Provides Braille output and routing-key input for the Phase 3 screen reader
using BRLTTY's Python BrlAPI bindings.

Compatible with Brailliant BI 40X (HumanWare, hw driver) and all other
displays supported by BRLTTY's `hw` and `hid` drivers.

Usage:
    from a11y.braille.brltty import BrailleDisplay
    brl = BrailleDisplay()
    brl.connect()
    brl.write_text("Schaltfläche OK")
    brl.close()

Requirements:
    brltty built with hw driver and Python bindings (libbrlapi)
    brltty running: brltty -b hw -d usb: -A auth=none

BRLTTY version: 6.9.1+ (required for Darwin HID-class USB transport, PR #530)
HumanWare Brailliant BI 40X: VID 0x1C71 PID 0xC131, hw driver, HID protocol
"""

import threading
import queue
from typing import Callable

# BrlAPI Python bindings (installed with BRLTTY)
try:
    import brlapi
    BRLAPI_AVAILABLE = True
except ImportError:
    BRLAPI_AVAILABLE = False


class BrailleDisplay:
    """BrlAPI client for BRLTTY Braille display integration."""

    def __init__(self, host: str = "localhost", auth: str = ""):
        self.host = host
        self.auth = auth
        self._conn = None
        self._cells = 0
        self._running = False
        self._key_thread = None
        self._on_routing_key: Callable[[int], None] | None = None

    @property
    def available(self) -> bool:
        return BRLAPI_AVAILABLE

    @property
    def connected(self) -> bool:
        return self._conn is not None

    @property
    def cell_count(self) -> int:
        return self._cells

    def connect(self) -> bool:
        if not BRLAPI_AVAILABLE:
            print("BrlAPI not available — install BRLTTY with Python bindings")
            return False
        try:
            self._conn = brlapi.Connection(host=self.host, auth=self.auth)
            self._cells = self._conn.displaySize[0]
            # Claim the driver so we can write Braille
            self._conn.enterTtyMode()
            print(f"BrlAPI connected: {self._cells} cells")
            self._start_key_listener()
            return True
        except brlapi.ConnectionError as e:
            print(f"BrlAPI connection failed: {e}")
            print("Is BRLTTY running? Try: brltty -b hw -d usb: -A auth=none")
            return False

    def write_text(self, text: str, cursor: int = brlapi.CURSOR_OFF if BRLAPI_AVAILABLE else -1):
        """Write text to the Braille display, truncated to cell count."""
        if not self._conn:
            return
        try:
            # Pad or truncate to cell count
            padded = (text + " " * self._cells)[:self._cells]
            self._conn.writeText(cursor, padded)
        except brlapi.ConnectionError:
            self._conn = None

    def write_dots(self, dots: list[int]):
        """Write raw dot patterns (list of byte values, one per cell)."""
        if not self._conn:
            return
        try:
            padded = (dots + [0] * self._cells)[:self._cells]
            self._conn.writeDots(bytes(padded))
        except brlapi.ConnectionError:
            self._conn = None

    def set_routing_key_handler(self, handler: Callable[[int], None]):
        """Called when user presses a routing key (cell index 0-based)."""
        self._on_routing_key = handler

    def _start_key_listener(self):
        self._running = True
        self._key_thread = threading.Thread(target=self._key_loop, daemon=True)
        self._key_thread.start()

    def _key_loop(self):
        """Read Braille display key events in a background thread."""
        while self._running and self._conn:
            try:
                key = self._conn.readKey(block=True)
                if key is None:
                    break
                # Routing keys: BRL_CMD_ROUTE + cell_index
                # Navigation keys: mapped to screen reader commands
                self._handle_key(key)
            except brlapi.ConnectionError:
                break

    def _handle_key(self, key: int):
        """Route Braille key events to screen reader commands."""
        if not BRLAPI_AVAILABLE:
            return
        # Routing keys
        if key & brlapi.KEY_TYPE_CMD:
            cmd = key & brlapi.KEY_CMD_MASK
            arg = (key & brlapi.KEY_CMD_ARG_MASK) >> brlapi.KEY_CMD_ARG_SHIFT
            if cmd == brlapi.KEY_CMD_ROUTE and self._on_routing_key:
                self._on_routing_key(arg)

    def close(self):
        self._running = False
        if self._conn:
            try:
                self._conn.leaveRawMode()
                self._conn.close()
            except Exception:
                pass
            self._conn = None


# BRL-Navigator: maps screen reader focus events to Braille output
class BrailleNavigator:
    """
    Integrates BrailleDisplay with the Phase 1 screen reader.
    
    Usage:
        nav = BrailleNavigator(display)
        nav.on_focus("Schaltfläche OK")  # called by FocusObserver
    """

    def __init__(self, display: BrailleDisplay):
        self.display = display
        self._current_text = ""
        self._scroll_offset = 0

    def on_focus(self, description: str):
        """Update Braille display when focused element changes."""
        self._current_text = description
        self._scroll_offset = 0
        self._render()

    def _render(self):
        cells = self.display.cell_count or 40
        text = self._current_text
        if len(text) > cells:
            # Show scrolled view
            text = text[self._scroll_offset:self._scroll_offset + cells]
        self.display.write_text(text)

    def scroll_right(self):
        cells = self.display.cell_count or 40
        if self._scroll_offset + cells < len(self._current_text):
            self._scroll_offset += cells
            self._render()

    def scroll_left(self):
        self._scroll_offset = max(0, self._scroll_offset - (self.display.cell_count or 40))
        self._render()
