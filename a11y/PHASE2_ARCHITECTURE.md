# SiliconForest Accessibility — Phase 2 Architecture

> Findings from live macOS tracing (Nov 2026) + consultation with Manuel Osswald (Apple Seed Member)

## Stack overview (macOS, reconstructed via live tools)

```
App process                        VoiceOver / Screen Reader
──────────────────────────────     ──────────────────────────
NSAccessibilityButton protocol     SCROutputBrailleComponent
       | (AppKit auto-bridge)             |
       v                                  |
AXUIElementRef (CFType)  <-------- AXObserver (Mach-port listener)
       |                                  |
       +---------- Mach port -------------+
                       |
               AccessibilityUIServer
               (Launchd: com.apple.AccessibilityUIServer)
                       |
               AXGuestPassServices  <- trust token per app
```

## Key services observed via launchctl list (macOS)

| Launchd name                              | PID  | Role                         |
|-------------------------------------------|------|------------------------------|
| com.apple.AccessibilityUIServer           | 1153 | Central AX hub               |
| com.apple.VoiceOver                       | 1047 | Screen reader                |
| com.apple.accessibility.heard             | 1268 | Voice command listener       |
| com.apple.AccessibilityVisualsAgent       | 1255 | Visual accessibility overlays|

## Communication flow (live log stream output)

1. App implements NSAccessibilityElement protocols (AppKit layer)
2. AppKit registers the app with **AccessibilityUIServer** via Mach port
   (AXGuestPassServices issues a trust token: `AXUIServerGuestPassActionHandler`)
3. Focus change: `MenuBarAgent` fires
   `_fireObserverID:forApplication:withAXElementRef:userInfo:`
4. VoiceOver `SCRCThread pool` picks it up → routes to `SCROutputBrailleComponent`

## What SiliconForest needs to implement (Phase 2)

### Core bridge (Python layer — now in `a11y/ax/bridge.py`)
- AXUIElement class (mirror of AXUIElementRef)
- NSAccessibilityElement / Button / StaticText / CheckBox ABCs
- AXObserver notification bus
- bootstrap_register / bootstrap_look_up (Launchd equivalent)

### Runtime (C/Swift — TODO)
- [ ] Launchd service: `com.siliconforest.AccessibilityUIServer`
- [ ] AXGuestPassServices equivalent (app trust/registration)
- [ ] Mach-port message loop connecting apps to our AX hub

### Chonkstep (Wayland compositor) integration (TODO)
- [ ] AT-SPI Device Grab for keyboard event routing to screen reader
- [ ] AXBridge: AXUIElement tree -> AT-SPI D-Bus (for BRLTTY etc.)

### For app developers
Apps implement `NSAccessibilityElement` from `a11y/ax/bridge.py`.
Our SDK walks these at runtime to auto-generate the AX tree.
Same developer experience as AppKit on macOS.

## Tracing methodology (SIP-enabled, no bypass needed)

```
log stream --predicate 'process == "AccessibilityUIServer" OR process == "VoiceOver"'
launchctl list | grep -i access
otool -L AccessibilityUIServer  # -> reveals AXGuestPassServices dependency
strings AccessibilityUIServer   # -> reveals GuestPassActionHandler class names
```

## References

- `AXUIElement.h` (public): HIServices.framework in Xcode SDK
- `NSAccessibilityProtocols.h` (public): AppKit.framework in Xcode SDK  
- Private internals reconstructed without SIP bypass via log stream + strings + otool
