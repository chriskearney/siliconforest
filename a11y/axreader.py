#!/usr/bin/env python3
"""SiliconForest Phase-1 Screen Reader (axreader.py)

Minimal screen reader for Darwin/XNU using native AXUIElement API.
Speaks the focused element (role + name + value) on every focus change.
No AT-SPI required — uses macOS Accessibility API directly via ctypes.

Requires:
  - eSpeak-NG: brew install espeak-ng
  - Accessibility permission granted to this process (System Settings → Privacy → Accessibility)

Usage:
  python3 axreader.py

Phase 1 navigation:
  Tab/Shift+Tab    Move between focusable elements
  Arrows           Text navigation
  Space/Return     Activate

Part of: https://github.com/chriskearney/siliconforest/issues/71
"""

import ctypes
import ctypes.util
import subprocess
import sys
import time
import threading

# ---------------------------------------------------------------------------
# CoreFoundation / ApplicationServices bindings (minimal)
# ---------------------------------------------------------------------------

CF = ctypes.CDLL("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")
AS = ctypes.CDLL("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices")

CF.CFStringGetCStringPtr.restype = ctypes.c_char_p
CF.CFStringGetCStringPtr.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
CF.CFRelease.argtypes = [ctypes.c_void_p]
CF.CFStringCreateWithCString.restype = ctypes.c_void_p
CF.CFStringCreateWithCString.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_uint32]

# AX API
AS.AXUIElementCreateSystemWide.restype = ctypes.c_void_p
AS.AXUIElementCopyAttributeValue.restype = ctypes.c_int
AS.AXUIElementCopyAttributeValue.argtypes = [
    ctypes.c_void_p, ctypes.c_void_p, ctypes.POINTER(ctypes.c_void_p)]
AS.AXObserverCreate.restype = ctypes.c_int
AS.AXObserverGetRunLoopSource.restype = ctypes.c_void_p

kCFStringEncodingUTF8 = 0x08000100

AX_FOCUSED = "AXFocusedUIElement"
AX_ROLE = "AXRole"
AX_TITLE = "AXTitle"
AX_VALUE = "AXValue"
AX_DESCRIPTION = "AXDescription"


def cf_str(s: str) -> ctypes.c_void_p:
    return CF.CFStringCreateWithCString(None, s.encode("utf-8"), kCFStringEncodingUTF8)


def ax_str(ref) -> str | None:
    if not ref:
        return None
    ptr = CF.CFStringGetCStringPtr(ref, kCFStringEncodingUTF8)
    if ptr:
        return ptr.decode("utf-8", errors="replace")
    buf = ctypes.create_string_buffer(512)
    if CF.CFStringGetCString(ref, buf, 512, kCFStringEncodingUTF8):
        return buf.value.decode("utf-8", errors="replace")
    return None


def get_ax_attr(element, attr: str) -> str | None:
    key = cf_str(attr)
    val = ctypes.c_void_p()
    err = AS.AXUIElementCopyAttributeValue(element, key, ctypes.byref(val))
    CF.CFRelease(key)
    if err != 0 or not val.value:
        return None
    result = ax_str(val.value)
    CF.CFRelease(val.value)
    return result


def get_focused_element():
    sys_elem = AS.AXUIElementCreateSystemWide()
    focused = ctypes.c_void_p()
    key = cf_str(AX_FOCUSED)
    err = AS.AXUIElementCopyAttributeValue(sys_elem, key, ctypes.byref(focused))
    CF.CFRelease(key)
    CF.CFRelease(sys_elem)
    if err != 0 or not focused.value:
        return None
    return focused.value


def describe_element(element) -> str:
    role = get_ax_attr(element, AX_ROLE) or "unknown"
    title = get_ax_attr(element, AX_TITLE)
    value = get_ax_attr(element, AX_VALUE)
    desc = get_ax_attr(element, AX_DESCRIPTION)
    # Clean up role (remove "AX" prefix)
    role_clean = role.replace("AX", "").lower()
    parts = [role_clean]
    if title:
        parts.append(title)
    elif desc:
        parts.append(desc)
    if value and role_clean not in ("textfield", "textarea"):
        parts.append(value)
    return ", ".join(parts)


# ---------------------------------------------------------------------------
# TTS via eSpeak-NG
# ---------------------------------------------------------------------------

_tts_lock = threading.Lock()
_tts_proc = None


def speak(text: str, interrupt: bool = True):
    global _tts_proc
    if not text.strip():
        return
    with _tts_lock:
        if interrupt and _tts_proc and _tts_proc.poll() is None:
            _tts_proc.terminate()
        _tts_proc = subprocess.Popen(
            ["espeak-ng", "-v", "de", "--", text],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )


# ---------------------------------------------------------------------------
# Focus polling loop (Phase 1 — no AT-SPI observer needed)
# ---------------------------------------------------------------------------

def poll_focus():
    last_element = None
    last_desc = ""
    print("SiliconForest axreader running. Press Ctrl+C to stop.", flush=True)
    speak("Bildschirmleser aktiv")
    while True:
        try:
            elem = get_focused_element()
            if elem and elem != last_element:
                desc = describe_element(elem)
                if desc != last_desc:
                    print(f"Focus: {desc}", flush=True)
                    speak(desc)
                    last_desc = desc
                last_element = elem
        except Exception as e:
            print(f"Error: {e}", flush=True)
        time.sleep(0.1)


if __name__ == "__main__":
    # Check accessibility permission
    syswide = AS.AXUIElementCreateSystemWide()
    if not syswide:
        print("ERROR: Cannot create AX system-wide element.", file=sys.stderr)
        print("Grant Accessibility permission to Terminal in System Settings → Privacy & Security → Accessibility", file=sys.stderr)
        sys.exit(1)
    CF.CFRelease(syswide)
    poll_focus()
