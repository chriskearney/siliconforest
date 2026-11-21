# SiliconForest Accessibility Layer

Phase 1 screen reader implementation for SiliconForest.

## Status

- [x] Issues filed: #71 (roadmap), #72 (navigation), #73 (TTS)
- [x] eSpeak-NG installed (brew install espeak-ng)
- [x] AX focus observer (`a11y/ax/observer.py`)
- [x] eSpeak-NG TTS backend (`a11y/tts/espeak.py`)
- [x] Phase-1 screen reader entry point (`a11y/screenreader.py`)
- [ ] NSAccessibilityProtocol stub in AppKit (upstream work needed)
- [ ] at-spi2-core port to Darwin (Phase 2)
- [ ] AX-Bridge: AXUIElement → AT-SPI D-Bus (Phase 2)
- [ ] Chonkstep AT-SPI Device Grab (Phase 2)
- [ ] BRLTTY on Darwin (Phase 3)

## Quick start (macOS only, until SiliconForest runs on hardware)

```bash
brew install espeak-ng
# Grant Accessibility permission to Terminal:
# System Settings → Privacy & Security → Accessibility → Terminal ✓
python3 a11y/axreader.py
```

## Architecture

See issue #71 for the full layer cake.

```
Mac-Apps
  │ NSAccessibilityProtocol
  ▼
a11y/ax/observer.py  — polls AXFocusedUIElement
  ▼
a11y/screenreader.py  — calls TTS on focus change
  ▼
a11y/tts/espeak.py  — eSpeak-NG subprocess / libespeak-ng.dylib
```

Phase 2 replaces the AX observer with a full AT-SPI bridge so that Orca
can run unchanged.
