"""a11y/ax/observer.py — AXUIElement focus observer for SiliconForest

Monitors the system-wide focused UI element using the macOS Accessibility API.
Calls a callback whenever focus changes to a new element.

Part of the Phase 1 screen reader implementation.
No AT-SPI or D-Bus required — uses Darwin's native AXUIElement directly.

Reference: https://github.com/chriskearney/siliconforest/issues/71
"""

import ctypes
import time
import threading
from typing import Callable

CF = ctypes.CDLL("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")
AS = ctypes.CDLL("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices")

CF.CFStringGetCStringPtr.restype = ctypes.c_char_p
CF.CFStringGetCStringPtr.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
CF.CFStringCreateWithCString.restype = ctypes.c_void_p
CF.CFStringCreateWithCString.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_uint32]
CF.CFRelease.argtypes = [ctypes.c_void_p]
AS.AXUIElementCreateSystemWide.restype = ctypes.c_void_p
AS.AXUIElementCopyAttributeValue.restype = ctypes.c_int
AS.AXUIElementCopyAttributeValue.argtypes = [
    ctypes.c_void_p, ctypes.c_void_p, ctypes.POINTER(ctypes.c_void_p)]

kCFStringEncodingUTF8 = 0x08000100

ROLE_LABELS = {
    "AXButton": "Schaltfläche",
    "AXCheckBox": "Kontrollkästchen",
    "AXTextField": "Textfeld",
    "AXTextArea": "Textbereich",
    "AXStaticText": "Text",
    "AXLink": "Link",
    "AXList": "Liste",
    "AXListItem": "Listeneintrag",
    "AXMenu": "Menü",
    "AXMenuItem": "Menüeintrag",
    "AXWindow": "Fenster",
    "AXHeading": "Überschrift",
    "AXSlider": "Schieberegler",
    "AXComboBox": "Kombinationsfeld",
    "AXRadioButton": "Optionsfeld",
    "AXTable": "Tabelle",
    "AXCell": "Zelle",
    "AXRow": "Zeile",
    "AXGroup": "Gruppe",
    "AXScrollArea": "Scrollbereich",
    "AXImage": "Bild",
    "AXWebArea": "Webinhalt",
    "AXUnknown": "Unbekannt",
}


def _cf_str(s: str):
    return CF.CFStringCreateWithCString(None, s.encode("utf-8"), kCFStringEncodingUTF8)


def _ax_str(ref) -> str | None:
    if not ref:
        return None
    ptr = CF.CFStringGetCStringPtr(ref, kCFStringEncodingUTF8)
    if ptr:
        return ptr.decode("utf-8", errors="replace")
    buf = ctypes.create_string_buffer(1024)
    if CF.CFStringGetCString(ref, buf, 1024, kCFStringEncodingUTF8):
        return buf.value.decode("utf-8", errors="replace")
    return None


def _get_attr(element, attr: str) -> str | None:
    key = _cf_str(attr)
    val = ctypes.c_void_p()
    err = AS.AXUIElementCopyAttributeValue(element, key, ctypes.byref(val))
    CF.CFRelease(key)
    if err != 0 or not val.value:
        return None
    result = _ax_str(val.value)
    CF.CFRelease(val.value)
    return result


def describe_element(element) -> str:
    """Returns a human-readable description for TTS output."""
    role = _get_attr(element, "AXRole") or "AXUnknown"
    role_label = ROLE_LABELS.get(role, role.replace("AX", ""))
    title = _get_attr(element, "AXTitle")
    desc = _get_attr(element, "AXDescription")
    value = _get_attr(element, "AXValue")

    parts = [role_label]
    if title:
        parts.append(title)
    elif desc:
        parts.append(desc)
    if value and role not in ("AXTextField", "AXTextArea", "AXStaticText"):
        parts.append(value)
    return ", ".join(p for p in parts if p)


class FocusObserver:
    """Polls system-wide focused element and calls on_focus on changes."""

    def __init__(self, on_focus: Callable[[str], None], poll_interval: float = 0.1):
        self.on_focus = on_focus
        self.poll_interval = poll_interval
        self._last = None
        self._last_desc = ""
        self._running = False
        self._thread = None

    def start(self):
        self._running = True
        self._thread = threading.Thread(target=self._poll, daemon=True)
        self._thread.start()

    def stop(self):
        self._running = False

    def _poll(self):
        sys_elem = AS.AXUIElementCreateSystemWide()
        key = _cf_str("AXFocusedUIElement")
        while self._running:
            try:
                focused = ctypes.c_void_p()
                err = AS.AXUIElementCopyAttributeValue(sys_elem, key, ctypes.byref(focused))
                if err == 0 and focused.value and focused.value != self._last:
                    desc = describe_element(focused.value)
                    if desc != self._last_desc:
                        self.on_focus(desc)
                        self._last_desc = desc
                    self._last = focused.value
                    CF.CFRelease(focused.value)
            except Exception:
                pass
            time.sleep(self.poll_interval)
        CF.CFRelease(key)
        CF.CFRelease(sys_elem)
