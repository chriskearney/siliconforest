"""
a11y/ax/bridge.py — SiliconForest AX Bridge (Phase 2)

Implements the two-layer accessibility stack that Manuel Osswald described:
  Layer 1: AXUIElement-compatible C-API (via ctypes, public Carbon/HIServices spec)
  Layer 2: NSAccessibilityProtocol-compatible Python ABC (AppKit protocol mirror)

Architecture discovered via live tracing on macOS (Nov 2026):
  - Processes register with Launchd as "com.apple.AccessibilityUIServer"
  - VoiceOver communicates via Mach ports using AXUIElementRef
  - AppKit auto-generates AX tree from NSAccessibilityElement protocol impls
  - SCROutputBrailleComponent in ScreenReaderCore consumes tree for Braille output

For SiliconForest: we re-implement the same surface using Darwin Mach primitives.
Key insight (Manuel Osswald): apps must LINK against our SDK for native elements
to become automatically accessible — same as AppKit apps get NSAccessibility free.
"""

from __future__ import annotations
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Optional, List, Any


# ---------------------------------------------------------------------------
# AXError codes (from AXError.h, public HIServices API)
# ---------------------------------------------------------------------------

class AXError:
    Success                      = 0
    Failure                      = -25200
    InvalidUIElement             = -25201
    InvalidObserver              = -25202
    CannotComplete               = -25203
    AttributeUnsupported         = -25204
    ActionUnsupported            = -25205
    NotificationUnsupported      = -25206
    NotImplemented               = -25208
    NotificationAlreadyRegistered = -25209
    NotificationNotRegistered    = -25210
    APIDisabled                  = -25211
    NoValue                      = -25212
    ParameterizedAttributeUnsupported = -25213
    NotEnoughPrecision           = -25214


# ---------------------------------------------------------------------------
# Layer 1: AXUIElement-compatible Python class
# Maps to AXUIElementRef (CFTypeRef) in Carbon/HIServices.
# On SiliconForest: will wrap Mach-port handle to the app AX server.
# On macOS: could wrap real HIServices calls via ctypes.
# ---------------------------------------------------------------------------

@dataclass
class AXUIElement:
    """
    Python representation of AXUIElementRef.

    Bootstrap port names observed via launchctl list (macOS, Nov 2026):
      com.apple.AccessibilityUIServer  (PID 1153) - central AX hub
      com.apple.VoiceOver              (PID 1047) - screen reader
    SiliconForest equivalent: com.siliconforest.AccessibilityUIServer
    """
    pid: int
    role: str = "AXUnknown"
    label: Optional[str] = None
    value: Optional[Any] = None
    children: List["AXUIElement"] = field(default_factory=list)
    parent: Optional["AXUIElement"] = None
    frame: tuple = (0.0, 0.0, 0.0, 0.0)  # x, y, w, h
    is_focused: bool = False

    # AXAttribute constants (from AXAttributeConstants.h, public)
    ATTR_ROLE        = "AXRole"
    ATTR_LABEL       = "AXLabel"
    ATTR_VALUE       = "AXValue"
    ATTR_CHILDREN    = "AXChildren"
    ATTR_PARENT      = "AXParent"
    ATTR_POSITION    = "AXPosition"
    ATTR_SIZE        = "AXSize"
    ATTR_FOCUSED     = "AXFocused"
    ATTR_TITLE       = "AXTitle"
    ATTR_DESCRIPTION = "AXDescription"

    def copy_attribute_value(self, attribute: str) -> tuple:
        """AXUIElementCopyAttributeValue equivalent."""
        mapping = {
            self.ATTR_ROLE:     self.role,
            self.ATTR_LABEL:    self.label,
            self.ATTR_VALUE:    self.value,
            self.ATTR_CHILDREN: self.children,
            self.ATTR_PARENT:   self.parent,
            self.ATTR_FOCUSED:  self.is_focused,
        }
        if attribute in mapping:
            return AXError.Success, mapping[attribute]
        return AXError.AttributeUnsupported, None

    def copy_attribute_names(self) -> tuple:
        """AXUIElementCopyAttributeNames equivalent."""
        return AXError.Success, [
            self.ATTR_ROLE, self.ATTR_LABEL, self.ATTR_VALUE,
            self.ATTR_CHILDREN, self.ATTR_PARENT, self.ATTR_FOCUSED,
        ]

    @classmethod
    def create_system_wide(cls) -> "AXUIElement":
        """AXUIElementCreateSystemWide — root of the AX tree."""
        return cls(pid=0, role="AXApplication")

    @classmethod
    def create_with_pid(cls, pid: int) -> "AXUIElement":
        """AXUIElementCreateWithPid — per-app entry point."""
        return cls(pid=pid, role="AXApplication")


# ---------------------------------------------------------------------------
# Layer 2: NSAccessibilityProtocol mirror (Python ABCs)
# Apps implement these; our SDK auto-builds the AX tree at runtime.
# Mirrors NSAccessibilityProtocols.h from AppKit (Xcode SDK, public).
# ---------------------------------------------------------------------------

class NSAccessibilityElement(ABC):
    """
    Mirror of @protocol NSAccessibilityElement <NSObject> (AppKit).
    @required methods are abstract; @optional have default implementations.
    """

    @abstractmethod
    def accessibility_frame(self) -> tuple:
        """@required — NSRect accessibilityFrame: bounding box on screen."""
        ...

    @abstractmethod
    def accessibility_parent(self) -> Optional["NSAccessibilityElement"]:
        """@required — id accessibilityParent."""
        ...

    def is_accessibility_focused(self) -> bool:
        """@optional — BOOL isAccessibilityFocused."""
        return False

    def accessibility_identifier(self) -> Optional[str]:
        """@optional — NSString* accessibilityIdentifier."""
        return None

    def to_ax_element(self, pid: int) -> AXUIElement:
        """Convert this protocol impl to AXUIElement for the bridge."""
        x, y, w, h = self.accessibility_frame()
        return AXUIElement(
            pid=pid,
            role=type(self).__name__,
            is_focused=self.is_accessibility_focused(),
            frame=(x, y, w, h),
        )


class NSAccessibilityButton(NSAccessibilityElement):
    """Mirror of @protocol NSAccessibilityButton <NSAccessibilityElement>."""

    @abstractmethod
    def accessibility_label(self) -> Optional[str]:
        """@required — NSString* accessibilityLabel."""
        ...

    @abstractmethod
    def accessibility_perform_press(self) -> bool:
        """@required — BOOL accessibilityPerformPress: activate button."""
        ...


class NSAccessibilityStaticText(NSAccessibilityElement):
    """Mirror of @protocol NSAccessibilityStaticText."""

    @abstractmethod
    def accessibility_value(self) -> Optional[str]:
        """@required — NSString* accessibilityValue."""
        ...

    def accessibility_string_for_range(self, start: int, length: int) -> Optional[str]:
        """@optional — substring for Braille cell-by-cell navigation."""
        v = self.accessibility_value()
        return v[start:start+length] if v else None


class NSAccessibilityCheckBox(NSAccessibilityButton):
    """Mirror of @protocol NSAccessibilityCheckBox."""

    @abstractmethod
    def accessibility_value(self) -> Optional[int]:
        """@required — NSNumber* accessibilityValue (0=off, 1=on, 2=mixed)."""
        ...


class NSAccessibilityGroup(NSAccessibilityElement):
    """Mirror of @protocol NSAccessibilityGroup — container element."""
    pass


# ---------------------------------------------------------------------------
# AXObserver — notification bus
# Maps to AXObserverRef / AXObserverCreate / AXObserverAddNotification.
# On SiliconForest: Mach-message listener on our bootstrap port.
#
# Live log stream showed VoiceOver SCRCThread pool calling:
#   _fireObserverID:forApplication:withAXElementRef:userInfo:
# This is the internal equivalent of what AXObserver exposes publicly.
# ---------------------------------------------------------------------------

# AXNotification names (from AXNotificationConstants.h, public)
AX_NOTIFICATION_FOCUSED_UI_ELEMENT_CHANGED  = "AXFocusedUIElementChanged"
AX_NOTIFICATION_VALUE_CHANGED               = "AXValueChanged"
AX_NOTIFICATION_SELECTED_TEXT_CHANGED       = "AXSelectedTextChanged"
AX_NOTIFICATION_WINDOW_CREATED              = "AXWindowCreated"
AX_NOTIFICATION_UI_ELEMENT_DESTROYED        = "AXUIElementDestroyed"
AX_NOTIFICATION_MENU_OPENED                 = "AXMenuOpened"
AX_NOTIFICATION_MENU_CLOSED                 = "AXMenuClosed"


class AXObserver:
    """
    Python mirror of AXObserverRef.
    On macOS: wraps CFRunLoop-based Mach-port listener.
    On SiliconForest: will use our own Mach-port bootstrap registration.
    """

    def __init__(self, pid: int):
        self.pid = pid
        self._handlers: dict = {}

    def add_notification(self, element: AXUIElement, notification: str, callback) -> int:
        """AXObserverAddNotification equivalent."""
        self._handlers.setdefault(notification, []).append((element, callback))
        return AXError.Success

    def remove_notification(self, element: AXUIElement, notification: str) -> int:
        """AXObserverRemoveNotification equivalent."""
        if notification in self._handlers:
            self._handlers[notification] = [
                (e, cb) for e, cb in self._handlers[notification]
                if e is not element
            ]
        return AXError.Success

    def fire(self, notification: str, element: AXUIElement, user_info: dict = None):
        """Called by SiliconForest AX runtime when an event fires."""
        for (_, cb) in self._handlers.get(notification, []):
            cb(self, element, notification, user_info or {})


# ---------------------------------------------------------------------------
# Bootstrap port registry
# On macOS: managed by Launchd (bootstrap_register / bootstrap_look_up).
# Service names observed via launchctl list (macOS, Nov 2026):
#   com.apple.AccessibilityUIServer, com.apple.VoiceOver,
#   com.apple.accessibility.heard
# SiliconForest equivalent: com.siliconforest.*
# ---------------------------------------------------------------------------

_bootstrap_registry: dict = {}


def bootstrap_register(service_name: str, handler) -> None:
    """Register an AX service (Launchd bootstrap_register equivalent)."""
    _bootstrap_registry[service_name] = handler


def bootstrap_look_up(service_name: str):
    """Look up a registered AX service (Launchd bootstrap_look_up equiv)."""
    return _bootstrap_registry.get(service_name)
