# Quake on SiliconForest

QuakeSpasm's macOS arm64 app, with its files unchanged, in a Chonkstep window on Mesa's OpenGL for
the M1 GPU, with the id Software Quake 1.06 shareware episode. No game data, app binary or
Apple binary is in this tree: `install.sh` fetches them, checks their hashes and stages them on the M1
under `/private/var/db/sfquake`.

## Which build

The official QuakeSpasm 0.97.0 Mac SDL2 zip has an `i386 x86_64` main executable, so it cannot run
on the M1. `install.sh` uses the Mac Source Ports universal build. Its DMG and `Info.plist` say 0.96.3;
the engine inside prints `QuakeSpasm v0.97.0`. Ironwail needs OpenGL 4.3 compute and has no supported Mac build.

## Pieces

| file | what |
| --- | --- |
| `install.sh` | run on the builder: fetch, verify, build `frameworks/`, stage on the M1 |
| `frameworks/ForceFeedback.c` | SDL2 links this framework; every call reports no such interface |
| `frameworks/IOKitFill.c` | re-exports a renamed copy of the M1's IOKit and adds the two mouse-acceleration calls the engine imports; both return `kIOReturnUnsupported` |
| `frameworks/sfquakestart.c` | inserted at launch: makes the app's `SDLMain` the delegate, because this build's `Info.plist` has no `NSMainNibFile` and the engine would never start |
| `../desktop/system/sf-open-quake` | the launcher; these libraries apply to the Quake process only |
| `../desktop/system/applications/com.macsourceports.QuakeSpasm.desktop` | the desktop entry. `Icon=` names the app bundle, so the dock decodes the app's own `QuakeSpasm.icns` in place, as for other Mac apps. The image is not in this tree. `install.sh` checks its hash and adds the dock pin once |

## Measured (23 November 2026, M1, panel on)

`GL_RENDERER: Apple M1 (G13G B1)`, `GL_VERSION: 4.6 (Compatibility Profile) Mesa 26.3.0-devel`.
`timedemo demo1` in a 1280x800 window with `vid_vsync 0`: 285.4 and 293.0 fps (969 frames). A run with
the panel off printed 504.4 fps and is not comparable. The audio device opens through CoreAudio and
the speakers consume its stream with 0 underruns.

## Not established

- Physical keyboard and mouse play. Quake holds Wayland keyboard focus, but a touch-bar F12 test never
  reached it as a key, so that test says nothing either way.
- Whether the sound is audible: the stream is measured, nobody has listened.
- `+map e1m1` on the command line had no effect in testing (the attract demo played). `map e1m1` from
  `autoexec.cfg` works.
- The engine cannot turn off mouse acceleration here (`IOHIDGetAccelerationWithKey` is unsupported).
- A white strip labelled "QuakeSpasm" shows between the title bar and the picture.
