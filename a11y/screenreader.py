"""a11y/screenreader.py — SiliconForest Phase 1 Screen Reader

Minimal screen reader: speaks the focused element on every focus change.
Requires eSpeak-NG (brew install espeak-ng) and Accessibility permission.

Usage: python3 -m a11y.screenreader

Part of: https://github.com/chriskearney/siliconforest/issues/71
"""

import sys
from a11y.ax.observer import FocusObserver
from a11y.tts.espeak import EspeakTTS


def main():
    tts = EspeakTTS(lang="de", rate=200)
    observer = FocusObserver(on_focus=lambda desc: tts.speak(desc, interrupt=True))

    print("SiliconForest screen reader starting…", flush=True)
    tts.speak("Bildschirmleser aktiv")
    observer.start()

    try:
        import signal
        signal.pause()
    except (KeyboardInterrupt, AttributeError):
        pass

    observer.stop()
    tts.stop()
    print("Screen reader stopped.", flush=True)


if __name__ == "__main__":
    main()
