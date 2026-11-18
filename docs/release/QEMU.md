<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 Chris Kearney and the SiliconForest contributors -->

# Trying SiliconForest in QEMU

SiliconForest is built for the 13-inch M1 MacBook Pro. Without one, the release's root
filesystem can still be started in QEMU's arm64 `virt` machine: the same root (desktop, dock,
terminal, Homebrew, shell tools) on QEMU's generic kernel collection instead of the M1's, with a
plain framebuffer instead of the M1's GPU. This page gives the commands and says exactly what one
run showed. It is not a substitute for the hardware: no GPU, Wi-Fi, sound, Touch Bar or M1 driver
is exercised here.

## What was shown, once

Run 20 of 18 November 2026, on an x86_64 Linux workstation (16 cores, other builds running, load
20 to 30), QEMU 11.1.0, TCG emulation, four virtual CPUs, 1 GiB of guest memory, a 1024x768
screen:

- QEMU's firmware loads the loader, the kernel finds the release root by its UUID and mounts it;
  launchd starts the root's services; the SSH server makes its host key; the first-start job
  writes the pointer set.
- About 135 s after QEMU started, the desktop draws the forest wallpaper. Then the dock appears:
  a launcher strip at the top left (Chonkstep Terminal, Firefox) and an instrument column at the
  top right (the SiliconForest mark, load, network, clock), and a terminal window with a `$`
  prompt.
- A command typed on QEMU's emulated USB keyboard runs in the terminal: `uname -m; echo
  typed-in-qemu` printed `arm64` and `typed-in-qemu`.
- The session ran its full 1,500 s and the compositor exited 0 (`QDDESK_PASS`).
- Under emulation the dock's instruments are slow enough that the dock retires them: they turn
  into labelled dead tiles (LOAD, NET, CLK). That is the dock protecting itself, not a failure.

The disk of that run was built by `release/image.nix` from the build outputs the owner's M1
carries, with the desktop built from this repository's sources and its patch series. The same
recipe built from a fresh clone (the commands below) is CODEX-BUILD's work and has not been run
through this path yet. Firefox was not started: Mozilla's bundle is not in the release (an
installer fetches it). Pointer input, a QEMU window on a real display, sound and networking were
not tried.

## What you need

- An x86_64 Linux machine with [Nix](https://nixos.org/download) (flakes enabled), network access
  for the pinned sources and Homebrew bottles, and room in the Nix store for a full build of the
  release (tens of GB; the build takes hours the first time).
- `python3`, `debugfs`, `e2fsck` (e2fsprogs) and `sfdisk` (util-linux) on the host for the two
  helper scripts. Any image viewer that reads PPM for the pictures.

## Commands

```sh
git clone https://github.com/chriskearney/siliconforest
cd siliconforest
# the release root on a QEMU disk (QEMU's firmware partition and kernel collection + the root)
nix build .#qemu-reference-image -o result-qemu
# QEMU and its arm64 firmware, pinned by the flake, with the run script
nix build .#qemu-runner -o result-runner
# a writable copy of the disk with QEMU's own desktop session (software rendering on the
# firmware framebuffer, USB keyboard and mouse); 1500 s session; no autopilot
sh release/image/qemu/prepare-run.sh result-qemu run 1500 none
# start it, save a picture of the screen every 30 s through QEMU's VNC socket, and type one
# command 150 s after the desktop's first frame
QD_RUN=result-runner/bin/siliconforest-qemu TYPE_AFTER=150 \
  sh release/image/qemu/run-vnc.sh run 5400 "uname -m; echo typed-in-qemu"
```

Run 20 used the host's own QEMU 11.1.0 with `qd_run.py` directly (no `QD_RUN`); the flake's pinned
QEMU has not been used for this path yet.

## What you get

- `run/shots/NNN.ppm`: a picture of the guest screen every 30 seconds.
- `run/out/serial.log`: the guest console. `WMSCALE initial` marks the desktop's first frame,
  `QDDESK_DESKTOP_RC=0` and `QDDESK_PASS` a session that ended normally.
- `run/out/result.json`: the run's summary (`PASS` when the session ended normally).
- `run/type.log`: when the command was typed.
- `sh release/image/qemu/extract-shots.sh run`: the session's records and the dock's log, read out
  of the disk copy afterwards (read only).

The disk copy is yours; the Nix output is never written. Delete `run` to start again.

## Known limits of the QEMU path

- QEMU's screen dump over QMP hung QEMU on the test machine while the desktop was drawing; the
  pictures therefore come through QEMU's VNC server (`release/image/qemu/vnc-shot.py`).
- Under emulation the terminal needs about 27 s to start; the desktop's default deadline is
  25 s. The QEMU session sets `CHONKSTEP_DARWIN_APP_READY_SECONDS=180` and
  `CHONKSTEP_DARWIN_AUTOPILOT_ARM_SECONDS=240`; the hardware keeps the defaults.
- On a busy host the kernel needs `no_lock_timeouts=1` (set on the QEMU disk), or a descheduled
  virtual CPU reads as a deadlock.
