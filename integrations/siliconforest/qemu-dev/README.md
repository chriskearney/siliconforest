# SiliconForest in QEMU

The SiliconForest userland on this Linux workstation, without the M1: upstream PureDarwin's
arm64 `virt` target under QEMU's TCG, with the M1's own arm64 binaries (compositor, terminal,
audio server, patched libSystem, session script). Status and open items:
`docs/roadmap/issues/SF-Q-qemu-dev.md`.

Nothing here uses the M1, the controller or the bench.

## Two ways to run it

| | Throw-away loop | Persistent install |
|---|---|---|
| Command | `tools/qemu_desktop.sh` | `tools/qemu_install.sh create`, `boot`, `update`, `reset`, `status` |
| Disk | a fresh copy of the template for every run (`runs/qemu-dev/<name>/disk.img`) | one disk that is kept: `runs/qemu-dev/install/disk.img` |
| What survives a run | nothing in the guest; screenshots, serial log and `result.json` on the host | the whole root filesystem: theme and scale choices, files in `/Users/sf`, anything installed |
| For | edit, build, run, look; unattended checks | using the system, package work, anything that needs state |

Both boot the same kernel collection and base image and start the desktop from a launchd job
(`org.siliconforest.qemu-desktop`), in parallel with upstream's root shell on the serial console.

### Which SiliconForest

The base image is built from the source `../rebase/pd.nix` selects: upstream's tip (`c713d8fb`)
by default since 12 November 2026, the old pin (`e7aa00a6`) with `SF_PD=pin` in the environment
of either script (`SF_PD=pin tools/qemu_desktop.sh ...`). With `SF_PD=pin`, `build-kc.nix` and
`build-image.nix` are the derivations they were before the switch. `qd_image.py` keeps the two
apart: every remembered Nix answer in `runs/qemu-dev/base/inputs.json` is keyed `pin: ...` or
`tip: ...` (keys without a source are from before the switch and are no longer read), and
templates are named `template-<pin|tip>-<kernel>-<variant>-<hash>.img`, so a run on one source
replaces only that source's older template. libSystem: a tip run stages the one the M1 RAM
root's base mapping names; a pin run always stages the pin build of `../libsystem-default`.
The audio server, its frameworks and `sfplay` are built from the run's source (at the tip: our
`/dev` backend on upstream's server, `../m1-sound/sysaudio/tools/sa_qemu.sh` is its check here).
The `wayland` variant exists at the pin only (at the tip it is about 100 derivations to build):
`SF_PD=pin tools/qemu_install.sh create --variant wayland`.

### Throw-away loop

```sh
tools/qemu_desktop.sh                      # headless: full autopilot, exit 0 = pass
tools/qemu_desktop.sh --only settle,settings --name themes
tools/qemu_desktop.sh --window             # a QEMU window, keyboard and pointer by hand
tools/qemu_desktop.sh --src runs/m1-desktop-010/<your worktree>   # build the compositor first
tools/qemu_desktop.sh --help
```

Output in `runs/qemu-dev/<name>/` (default name `last`): `serial.log` (the guest console),
`shots/*.png` (QMP `screendump` of the guest framebuffer: `desktop.png` when the desktop is up,
one every 10 s, `final.png`), `result.json` (status, times, the `WMAUTO` result lines),
`build.log` with `--src`. Pass/fail of an unattended run is the autopilot's own
`WMAUTO done result=ok`; by hand it is the compositor's exit status.

The window never goes full screen and never grabs the pointer (the guest sees a USB tablet, an
absolute pointer). It takes keys only while it has the host's focus. Headless is the default,
and a headless run has no `DISPLAY`/`WAYLAND_DISPLAY`.

### Persistent install

```sh
tools/qemu_install.sh create               # make the disk (minimal userland + our desktop + user sf)
tools/qemu_install.sh create --variant wayland   # the full userland instead (6 GiB root; boot it with --memory 2048)
tools/qemu_install.sh boot --window        # use it; close the window or wait for --seconds
tools/qemu_install.sh boot                 # headless, 120 s of desktop, screenshots
tools/qemu_install.sh boot --command 'ls -l /Users/sf; echo QDINSTALL_DONE'   # root shell, no desktop
tools/qemu_install.sh update --bin <compositor>     # new desktop binaries, everything else kept
tools/qemu_install.sh reset                # delete the disk
```

The root is the disk's ext4 partition, mounted read-write (`root_device on / (ext4, local)`).
The guest is usually stopped without unmounting (window closed, time over), so the session
runs `sync` every 5 s and every `boot` first repairs the filesystem on the host (journal replay
by `e2fsck`, `qd_image.py --fsck`). Shown: a file written to `/Users/sf` and a theme written to
the state directory in one boot are read back in the next.

## Interfaces other streams may rely on

- `qd_run.py --image IMG --out DIR [--command 'guest command'] --begin RE --up RE --end RE --passed RE
  [--input-seen RE] [--window] [--timeout S] [--shot-every S] [--smp N] [--memory MB] [--pointer tablet|mouse]
  [--qemu-arg ARG]...` boots any image of this kind and exits 0 (pass marker seen before the end
  marker), 1 (not), 2 (could not run). With `--command` it waits for the root shell prompt on the
  serial console and types the command; markers are regular expressions matched against the whole
  serial log, so a marker must not appear literally in the typed command (print it with
  `printf 'X_%s\n' END`, or end it with something the echo does not have). Extra disks go in with
  `--qemu-arg`. These options will not change meaning; new ones may be added.
- `qd_image.py --output IMG [--variant minimal|wayland] [--file SRC=/DEST]... [--data SRC=/DEST]...
  [--dir /PATH:UID:GID]... [--remove /PATH]... [--bootargs '...'] [--resolution WxH] [--kernel release|debug]`
  makes an image; `qd_image.py --fsck IMG` repairs one. `qd_image.partitions(img)`,
  `read_root(img, path)`, `write_root(img, files, dirs, remove)` are importable.
- The persistent disk: `runs/qemu-dev/install/disk.img`, GPT, partition 1 the ESP (loader,
  `kernel`, `boot-args.txt`), partition 2 the ext4 root (512 MiB in the minimal variant). One
  QEMU at a time: take `runs/qemu-dev/install/lock` with `flock` (as `boot` does). A writable
  `/opt/homebrew` is simply a directory on that root; for more room attach a second disk with
  `--qemu-arg` (the storage stream's runs show ext4 data disks working that way).
- Guest facts: root shell without a password on the serial console (`/dev/console`, zsh);
  launchd runs the daemons in `/System/Library/LaunchDaemons`; our session job writes to
  `/dev/console`; state directory `/private/var/db/desktop-state` (`XDG_STATE_HOME`).

## What is in the guest

Base image (`build-image.nix`): upstream `image-arm64-virt-minimal-release` at the tip `c713d8fb`
(`SF_PD=pin`: at the old pin `e7aa00a6`), RELEASE kernel, with three changes, all only for this target:

- `sfhid-publish-keyboard.patch` (in the kernel collection, `build-kc.nix`): `/dev/usb_hid_kbd`
  never appeared for QEMU's USB keyboard; one line in IOHIDFamily's event queue.
- `virtio-net-name-interface.patch` (same collection): nothing in a root without configd names
  network interfaces; the virtio driver asks IONetworkStack to, as the lab's Wi-Fi driver does.
- `loader-gop-mode.patch`: `sfgopmode=WxH` in the boot arguments selects the firmware graphics
  mode. The firmware's ramfb driver offers 640x480, 800x600 and 1024x768; the default here is
  1024x768.

`qd_image.py` then makes the template from it: the kernel's two 30 s `IOKitInitializeTime` waits
shortened in the binary (the M1 launcher's patch, extended to the RELEASE code shape), our boot
arguments (`no_lock_timeouts=1` is upstream's switch for emulated guests), and the slow-changing
files of the M1 RAM root (its base mapping without firmware and M1-only tools: fonts, xkb data,
the spawn-attribute libSystem, test clients; terminfo; desk picture; coreaudiod with its
frameworks and tools; `sf-dhcp`; `qemu-net-up`). A run adds the compositor, the terminal, the
session script and the launchd job. Templates are cached in `runs/qemu-dev/base/` by a hash of
their inputs; Nix store paths are remembered in `runs/qemu-dev/base/inputs.json` (`--refresh`
asks Nix again, which costs tens of seconds per expression).

Userland of the minimal variant: zsh on the console, toybox (about 65 applets: ls, cp, sed, awk,
grep, find, tar, vi, ...), launchd/launchctl, mount/umount, `ext4tool`, `gpt`, ping, netcat,
`netsetup`, `wifiutil`, mdnsd, notifyd, dtrace. No login, su, ifconfig, netstat, curl, ssh,
compiler, package tool or man pages. The `wayland` variant (`qemu_install.sh create --variant
wayland`, `build-image.nix --argstr variant wayland`) starts from upstream's
`image-arm64-virt-wayland` instead: the full userland without X11 (clang/llvm, cmake, ninja,
meson, make, autotools, python, git, curl, openssl, openssh, nano, gtk3, sway, netsurf, mesa,
configd, ...). That base is a build of about a hundred derivations including an arm64 LLVM
(built here once; it is in the Nix store). The install carries the Homebrew stream's libSystem
(`--libsystem homebrew`, issue 46); the throw-away loop keeps the M1 RAM root's unless asked.

QEMU machine: `virt,gic-version=3`, `-cpu neoverse-n2` (`max` hangs in the firmware), 2 vCPUs,
1 GiB (kernel start-up time grows with memory under TCG), virtio-blk disk, ramfb, virtio-net with
QEMU's user network, xHCI with a USB keyboard and a USB mouse (headless) or tablet (window).

## Same checks on the M6

`m6-hvf-check.py` copies a prepared disposable disk to the authorized Mac and boots it under HVF. It does not write the local disk. The Mac copy is `~/sf/runs/<name>/`.

```sh
python3 integrations/siliconforest/qemu-dev/m6-hvf-check.py \
  --disk "$SF_QEMU_RUN/disk.img" --run probeN --out "$SF_QEMU_RUN/m6"
```

`--disk` is a disposable image already prepared the way the public QEMU receipt prepares one (`prepare-run.sh <reference> <run> 1500 none` on that receipt's tree). SSH is `chrisk@10.1.1.92` with `~/.ssh/known_hosts_m6`, `HostKeyAlias=m6`, and strict host-key checking. `--self-test` checks the patcher without a disk or a host. The VNC helper shipped beside this script is the receipt's `vnc-shot.py`.

HVF's ID_AA64PFR0_EL1.GIC field reads 0, so an unpatched guest takes the GICv2 CPU-interface path while this `virt` machine is GICv3. On the disposable copy only, both detection sites replace the opening `mrs` with `movz x8, #0x100, lsl #16`. The scan is the 64 MiB window at offset 1 MiB, and each site must occur once. The guest line is `virt,gic-version=3`, `-accel hvf,kernel-irqchip=off`, `-cpu host`, 4 vCPUs, 1 GiB, ramfb, a USB keyboard and mouse, and a VNC unix socket. Homebrew QEMU on the Mac supplies the firmware.

The checker stamps `QDDESK_BEGIN` and `WMSCALE initial`, saves a frame 15 seconds later, types `uname -m; echo typed-in-qemu` through `vnc-shot.py` 150 seconds after the first frame, and saves a second frame. The terminal PTY is not the serial console. Read `after.ppm` for `arm64`, `typed-in-qemu`, and the returned prompt. A fetched serial excerpt drops lines that mention a host key; do not commit the guest's serial log.

On 18 November 2026, QEMU 11.1.3 on that Mac reached `QDDESK_BEGIN` at 46.3 s and `WMSCALE initial` at 46.5 s. The isolated-004 TCG receipt (QEMU 10.2.4, the same 4 vCPU, 1 GiB, and 1024×768 session shape) records 64.7 s and 81.3 s. The second frame showed the typed command, `arm64`, `typed-in-qemu`, and a prompt. The prepared hash differs from that receipt's prepared hash: debugfs rewrites the ext4 copy, and the GIC patch changes two instructions. The reference image was not modified. That run stopped after the typing frame, so it has no `QDDESK_PASS`.

## What this covers, and what it does not

| Area | In QEMU | Notes |
|---|---|---|
| Shell, window management, layout, menus, notices | yes | same compositor binary and code path as the M1's CPU renderer |
| Themes, display scale | yes | at most 1024x768, so 200% leaves a 512x384 desk; the M1 panel is 2560x1600 |
| Terminal (PTY, xterm emulation, scrollback, selection, clipboard) | yes | same binary |
| Wayland protocol (xdg-shell, shm, fractional scale, decorations) | yes | no dma-buf clients: there is no GPU |
| Session logic, state directory, launch and cleanup | yes | started by launchd here, by the console script on the M1 |
| Keyboard and pointer | through SFHID, as on the M1 | QEMU USB HID, not the M1's SPI keyboard and trackpad drivers |
| coreaudiod, volume keys, sound menu | server starts; no device | "no IOAudioEngine": volume phases report SKIPPED. No virtio or HDA sound here |
| Networking | Ethernet on QEMU's user network: en0, DHCP, DNS, TCP out | `qemu-net-up`; the Wi-Fi menu shows "No Wi-Fi hardware". No Wi-Fi interface, so nothing of the Wi-Fi menu's join path |
| AGX GL renderer, Mesa, dma-buf import | no | CPU renderer only |
| DCP/KMS page flips, backlight, display power (idle phase) | no | firmware framebuffer, no vblank, no backlight |
| Touch Bar, trackpad driver (multitouch, two-finger click), SPI keyboard | no | |
| Speakers/codec, speaker protection | no | |
| Wi-Fi hardware, Bluetooth | no | |
| Eight Apple cores, P/E scheduling, cpufreq, thermal | no | two emulated Neoverse-N2 cores |
| Kernel | upstream's RELEASE `virt` kernel | not the M1's T8103 collection; no M1 driver runs |
| Speed | emulated | see timings in the status doc; frame rates say nothing about the M1 |

A change proven here still needs one M1 boot for anything in the "no" rows, and for the GL
renderer's output of the same scene.
