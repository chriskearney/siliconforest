"""
a11y/axserver.py — SiliconForest AX UI Server daemon

Listens on /tmp/com.siliconforest.axuiserver (Unix domain socket).
Receives JSON events from AppKit (SFAccessibilityServer.m) and
Chonkstep (wm-darwin sf_ax_forward_key) and routes them to:
  - eSpeak-NG TTS (via a11y/tts/espeak.py)
  - BRLTTY (via a11y/braille/brltty.py)

Usage:
    python3 a11y/axserver.py [--braille] [--no-tts] [--verbose]

The screenreader client (a11y/screenreader.py) starts this automatically.
"""

import asyncio
import json
import os
import sys
import signal
import logging
import argparse

SOCKET_PATH = "/tmp/com.siliconforest.axuiserver"

logger = logging.getLogger("axserver")


# ---------------------------------------------------------------------------
# Event dispatcher
# ---------------------------------------------------------------------------

class AXEventDispatcher:
    """
    Routes incoming AX events to TTS and/or Braille output.
    Instantiated once; shared across all client connections.
    """

    def __init__(self, use_tts: bool = True, use_braille: bool = False, verbose: bool = False):
        self.use_tts = use_tts
        self.use_braille = use_braille
        self.verbose = verbose
        self._tts = None
        self._braille = None
        self._last_window = None
        self._last_role = None
        self._last_label = None

    async def setup(self):
        """Initialize TTS and Braille backends."""
        if self.use_tts:
            try:
                sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
                from a11y.tts.espeak import EspeakTTS
                self._tts = EspeakTTS()
                logger.info("TTS backend: eSpeak-NG ready")
            except Exception as e:
                logger.warning(f"TTS unavailable: {e}")
                self._tts = None

        if self.use_braille:
            try:
                from a11y.braille.brltty import BrailleNavigator
                self._braille = BrailleNavigator()
                logger.info("Braille backend: BRLTTY ready")
            except Exception as e:
                logger.warning(f"Braille unavailable: {e}")
                self._braille = None

    def _speak(self, text: str):
        """Speak via TTS (non-blocking)."""
        if self._tts and text:
            try:
                self._tts.speak(text)
            except Exception as e:
                logger.debug(f"TTS speak error: {e}")

    def _braille_write(self, text: str):
        """Write to Braille display (non-blocking)."""
        if self._braille and text:
            try:
                self._braille.write(text)
            except Exception as e:
                logger.debug(f"Braille write error: {e}")

    def _output(self, text: str):
        """Send to both TTS and Braille."""
        if self.verbose:
            print(f"[AX] {text}", flush=True)
        self._speak(text)
        self._braille_write(text)

    def dispatch(self, event: dict):
        """Route an AX event to the appropriate output."""
        t = event.get("type", "")

        if t == "focus_changed":
            role  = event.get("role", "AXUnknown")
            label = event.get("label", "")
            value = event.get("value", "")

            # Avoid repeating identical announcements
            if role == self._last_role and label == self._last_label:
                return
            self._last_role = role
            self._last_label = label

            # Build announcement: "Button OK" / "Text Field" / "Checkbox checked"
            role_name = _role_to_spoken(role)
            if value and value not in label:
                announcement = f"{label}, {role_name}, {value}" if label else f"{role_name}, {value}"
            elif label:
                announcement = f"{label}, {role_name}"
            else:
                announcement = role_name
            self._output(announcement)

        elif t == "window_activated":
            title = event.get("title", "")
            if title and title != self._last_window:
                self._last_window = title
                self._output(f"Fenster: {title}")

        elif t == "text_changed":
            text = event.get("text", "")
            # Only announce last character typed (live region, not full content)
            if text:
                self._output(text[-1])

        elif t == "key_event":
            # Key events from Chonkstep's AT-SPI grab:
            # Route to virtual cursor navigation (not yet implemented fully)
            evdev = event.get("evdev", 0)
            down  = event.get("down", False)
            if down and evdev == 1:  # Escape: deactivate screenreader
                logger.info("Escape pressed — AT-SPI grab release requested")

        elif t == "screenreader_active":
            active = event.get("active", True)
            self._output("Bildschirmleser aktiv" if active else "Bildschirmleser inaktiv")

        else:
            logger.debug(f"Unknown event type: {t!r}")


def _role_to_spoken(role: str) -> str:
    """Convert AXRole string to a spoken German word."""
    return {
        "AXButton":           "Schaltfläche",
        "AXStaticText":       "Text",
        "AXTextField":        "Eingabefeld",
        "AXTextArea":         "Textbereich",
        "AXCheckBox":         "Kontrollkästchen",
        "AXRadioButton":      "Optionsschaltfläche",
        "AXComboBox":         "Kombinationsfeld",
        "AXPopUpButton":      "Auswahlmenü",
        "AXMenuItem":         "Menüeintrag",
        "AXMenu":             "Menü",
        "AXMenuBar":          "Menüleiste",
        "AXWindow":           "Fenster",
        "AXSheet":            "Blatt",
        "AXGroup":            "Gruppe",
        "AXScrollArea":       "Rollbereich",
        "AXTable":            "Tabelle",
        "AXRow":              "Zeile",
        "AXCell":             "Zelle",
        "AXImage":            "Bild",
        "AXLink":             "Link",
        "AXApplication":      "Anwendung",
        "AXUnknown":          "Unbekannt",
    }.get(role, role.replace("AX", ""))


# ---------------------------------------------------------------------------
# Unix socket server
# ---------------------------------------------------------------------------

class AXServer:
    def __init__(self, dispatcher: AXEventDispatcher):
        self.dispatcher = dispatcher
        self._server = None

    async def handle_client(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        peer = writer.get_extra_info("peername", "unknown")
        logger.debug(f"Client connected: {peer}")
        buffer = b""
        try:
            while True:
                chunk = await reader.read(4096)
                if not chunk:
                    break
                buffer += chunk
                # Process all complete newline-delimited JSON messages
                while b"\n" in buffer:
                    line, buffer = buffer.split(b"\n", 1)
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        event = json.loads(line)
                        self.dispatcher.dispatch(event)
                    except json.JSONDecodeError as e:
                        logger.warning(f"JSON decode error: {e} — line={line!r}")
        except (asyncio.IncompleteReadError, ConnectionResetError):
            pass
        finally:
            writer.close()
            logger.debug(f"Client disconnected: {peer}")

    async def start(self):
        # Remove stale socket
        if os.path.exists(SOCKET_PATH):
            os.unlink(SOCKET_PATH)
        self._server = await asyncio.start_unix_server(
            self.handle_client, path=SOCKET_PATH
        )
        os.chmod(SOCKET_PATH, 0o666)  # world-writable: apps run as different users
        logger.info(f"AXUIServer listening on {SOCKET_PATH}")

    async def stop(self):
        if self._server:
            self._server.close()
            await self._server.wait_closed()
        if os.path.exists(SOCKET_PATH):
            os.unlink(SOCKET_PATH)
        logger.info("AXUIServer stopped")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

async def main():
    parser = argparse.ArgumentParser(description="SiliconForest AX UI Server")
    parser.add_argument("--braille",  action="store_true", help="Enable BRLTTY Braille output")
    parser.add_argument("--no-tts",   action="store_true", help="Disable eSpeak-NG TTS output")
    parser.add_argument("--verbose",  action="store_true", help="Print all events to stdout")
    parser.add_argument("--log-level", default="INFO", help="Logging level (DEBUG/INFO/WARNING)")
    args = parser.parse_args()

    logging.basicConfig(
        level=getattr(logging, args.log_level.upper(), logging.INFO),
        format="%(asctime)s %(name)s %(levelname)s %(message)s",
    )

    dispatcher = AXEventDispatcher(
        use_tts=not args.no_tts,
        use_braille=args.braille,
        verbose=args.verbose,
    )
    await dispatcher.setup()

    server = AXServer(dispatcher)
    await server.start()

    loop = asyncio.get_running_loop()
    stop_event = asyncio.Event()

    def _signal_handler():
        logger.info("Signal received — shutting down")
        stop_event.set()

    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, _signal_handler)

    logger.info("SiliconForest AXUIServer ready — waiting for AppKit events")
    await stop_event.wait()
    await server.stop()


if __name__ == "__main__":
    asyncio.run(main())
