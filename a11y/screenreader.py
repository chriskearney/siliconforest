"""a11y/screenreader.py - SiliconForest Screen Reader

TTS: OpenEVV/Eloquence (best) > eSpeak-NG (fallback)
Braille: BrlAPI/BRLTTY (auto, all displays)
Focus: AXUIElement polling

Usage: python3 -m a11y.screenreader [--no-braille] [--voice auto|eloquence|espeak]
"""
import argparse
from a11y.ax.observer import FocusObserver
from a11y.tts.espeak import EspeakTTS
from a11y.tts.openevv import OpenEVVTTS
from a11y.braille.brltty import BrailleDisplay, BrailleNavigator

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--no-braille", action="store_true")
    p.add_argument("--no-speech", action="store_true")
    p.add_argument("--lang", default="de")
    p.add_argument("--rate", type=int, default=200)
    p.add_argument("--voice", choices=["auto","eloquence","espeak"], default="auto")
    args = p.parse_args()

    tts = None
    if not args.no_speech:
        if args.voice in ("auto", "eloquence"):
            tts = OpenEVVTTS(lang=args.lang, rate=args.rate)
            if not tts.available:
                print("OpenEVV nicht verfuegbar, nutze eSpeak-NG")
                tts = EspeakTTS(lang=args.lang, rate=args.rate)
        else:
            tts = EspeakTTS(lang=args.lang, rate=args.rate)

    brl, nav = None, None
    if not args.no_braille:
        brl = BrailleDisplay()
        if brl.connect():
            nav = BrailleNavigator(brl)
            print(f"Braille: {brl.cell_count} Zellen", flush=True)
        else:
            brl = None

    def on_focus(desc):
        if tts: tts.speak(desc, interrupt=True)
        if nav: nav.on_focus(desc)
        print(f"Fokus: {desc}", flush=True)

    obs = FocusObserver(on_focus=on_focus, poll_interval=0.1)
    print("SiliconForest Screenreader startet...", flush=True)
    if tts: tts.speak("Bildschirmleser aktiv")
    if nav: brl.write_text("Bildschirmleser aktiv")
    obs.start()
    try:
        import signal; signal.pause()
    except (KeyboardInterrupt, AttributeError):
        pass
    obs.stop()
    if tts: tts.stop()
    if brl: brl.close()

if __name__ == "__main__":
    main()
