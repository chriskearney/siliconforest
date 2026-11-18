# Installing SiliconForest

SiliconForest is a Darwin system (a fork of PureDarwin) that starts natively on an Apple silicon
Mac. It is installed **beside macOS**, from macOS, with one command. macOS stays on the Mac,
stays the system that starts by default, and keeps its files; you choose SiliconForest when you
start the Mac. This page is the whole process, for someone who has never done it.

> **Where this stands (18 November 2026).** No SiliconForest release has been published, so
> the installer checks your Mac and shows what it would do (`--check`, `--dry-run`) and then
> refuses to install, saying why. Everything below is what the installer does once a release
> exists. It has been run end to end only against a model of a Mac's disk, not on a real one.
> The same disk-changing code (the Asahi Linux installer, see "Credits") put SiliconForest on
> the one M1 it runs on today, on 13 November 2026, with a hand-made kit. The first install
> with this installer on a real Mac is a planned test (`docs/roadmap/issues/SF-AJ-installer.md`).

## 1. Before you start

**Which Mac.** Only one model today: the **13-inch MacBook Pro with M1, 2020**. In macOS: Apple
menu > About This Mac says "MacBook Pro (13-inch, M1, 2020)"; in Terminal `sysctl -n hw.model`
prints `MacBookPro17,1`. Every other Mac is refused with a message that names it. (Other Macs:
section 13.)

**Which macOS.** macOS 13.5 or newer, up to macOS 26. The installer refuses older and newer
versions. Update macOS first if it is older (System Settings > General > Software Update).

**Space.** About 55 GB by default, which you can change: a 2.5 GB startup volume, a 0.5 GB boot
partition, and SiliconForest's own root (the release says its minimum; 48 GB by default). The
space comes out of macOS's container, and **macOS must keep at least 38 GB free afterwards** (the
margin the Asahi Linux project found macOS updates need). If it cannot, the installer says how
much it could offer instead and changes nothing.

**A backup.** The installer shrinks the macOS container. Apple's resize keeps every file and the
installer never writes to macOS's volumes, but a disk operation can fail (a power cut, existing
damage in the filesystem). Make a Time Machine backup to an external disk first. Local Time
Machine snapshots on the same disk are not a backup.

**Also needed.** An administrator account, logged in at the Mac's own screen (the installer and
Apple's recovery ask for its password); power connected; an internet connection; about an hour,
of which a few minutes need you. Downloads: the installer engine (22 MB), the SiliconForest
release (its size is in the release notes), and, from Apple's servers, parts of the macOS 13.5
restore image for your Mac (several hundred MB to about 1 GB).

## 2. What the installer will do to your disk

Before (a typical Mac):

    [ Apple system container ][ macOS                                   ][ Apple recovery ]

After:

    [ Apple system container ][ macOS (smaller) ][SF][B][ SiliconForest root ][ Apple recovery ]

- **macOS** is shrunk by the amount SiliconForest needs (`diskutil apfs resizeContainer`, Apple's
  own tool). If there is already enough unallocated space (for example after removing another
  system), nothing is shrunk.
- **SF**: a 2.5 GB APFS container named "SiliconForest". This is what the startup picker shows.
  It holds a small "stub" macOS built from Apple's macOS 13.5 restore files for your Mac (the
  boot firmware SiliconForest's drivers are written for, and a recovery system of its own) and
  SiliconForest's first boot stage. It is how Apple silicon Macs start any second system; the
  Asahi Linux project designed it.
- **B**: a 500 MB FAT partition named SFBOOT with SiliconForest's second boot stage and kernel
  (`sf/boot.bin`, `sf/kernel.bin`).
- **SiliconForest root**: the rest, holding SiliconForest's files (ext4).
- **Not touched:** macOS's volumes and your files, the Apple system and recovery containers,
  and any other system on the disk (Asahi Linux, for instance). Two things outside the new
  partitions do change: macOS's container gets smaller, and for the one start after the install
  SiliconForest is the startup disk (Apple's recovery step needs that; you set macOS back
  afterwards, section 6). If macOS's list of administrators in its Preboot volume is out of date,
  Apple's `diskutil apfs updatePreboot` refreshes it (the Asahi installer does this).

Every change goes through one function in the installer that refuses anything the plan you
confirmed does not name, and that stops if any partition that was there before moves or changes
size (other than the planned shrink of macOS).

## 3. The one command

Open Terminal (Applications > Utilities > Terminal) and paste:

    curl -fsSL https://raw.githubusercontent.com/chriskearney/siliconforest/main/install.sh | sh

To read it first, or to only look, which is a good idea:

    curl -fsSLO https://raw.githubusercontent.com/chriskearney/siliconforest/main/install.sh
    less install.sh
    sh install.sh --dry-run      # the full plan with sizes; changes nothing
    sh install.sh                # the install

Options: `--check` (what this Mac is and what is on its disk), `--dry-run`, `--size 80` (GB for
SiliconForest in all), `--uninstall`, `--update`, `--help`.

What you trust when you run it: the script itself, fetched over HTTPS from this repository. It
then checks everything else before using it: the installer engine against a SHA-256 written in
the script, the release's manifest against a signature made with the project's release key
(whose public half is in the script), and every release file against the SHA-256 the manifest
lists. A download cut short cannot run half a script (the script is one function called on its
last line). Nothing on the disk changes before you have seen the plan and typed a word.

## 4. Step by step

**Step 1: checks (nothing changes).** The installer prints the Mac, the macOS version, FileVault
and snapshot state, the disk as it is now, and any other systems on it. If something is wrong it
stops here with a line beginning `NO` that says what to do, for example:

    NO   This Mac (Mac17,2, board J704) is not supported. SiliconForest runs only on:
         MacBook Pro (13-inch, M1, 2020) (J293).
    Nothing was changed.

**Step 2: the plan (nothing changes).** It shows, numbered, exactly what will change: how far
macOS shrinks and how much free space macOS keeps, the three new partitions with their sizes,
and that nothing else is written. Choose another size with `--size`. If macOS cannot shrink
enough, it says why: often Time Machine snapshots or a pending macOS update hold space that macOS
shows as free (`tmutil listlocalsnapshots /` lists them; `sudo tmutil deletelocalsnapshots /`
removes local ones; or finish the macOS update).

**Step 3: your decision.** `Type "install" and press Return to make these changes`. Anything else
stops with nothing changed.

**Step 4: your password, then the work.** sudo asks for your macOS password. The installer reads
the disk again and continues only if it is still exactly as planned. Then it shrinks macOS (the
Mac may seem to pause for a minute: that is normal), downloads the stub's files from Apple, makes
the three partitions, writes the root, copies the Wi-Fi and Bluetooth firmware for your Mac
(section 7), and writes your Mac's partition identifiers into `sf/kernel.bin`. It asks for your
password once more to make SiliconForest the startup disk for the next start. Each step is logged.

**Step 5: the instructions for recovery.** The installer prints them (they are the Asahi Linux
installer's, which have worked for many thousands of installs) and shuts the Mac down:

1. Wait 25 seconds after the screen goes dark.
2. Press **and hold** the power button. Keep holding it, in one press, until "Loading startup
   options…" appears.
3. Choose **SiliconForest**, then Continue.
4. A "macOS Recovery" window may ask you to select a volume to recover: choose your normal macOS
   volume, and sign in with your macOS account when asked.
5. A Terminal window opens: "SiliconForest installer (second step)". Press Return.
6. It runs Apple's `bputil` and `kmutil`. Each warns that you are lowering the security of a
   system and asks for your macOS user name and password. Answer with your macOS account. A
   mistyped password just asks again.
7. "Installation complete! Press enter to reboot."

**Why a human has to do step 5.** On Apple silicon, every installed system has its own security
policy, and only the Mac's owner, in the recovery mode reached by holding the power button, can
allow a system that Apple did not sign. The policy you set applies to the SiliconForest volume
only (Apple calls the level Permissive Security). **macOS's own security level does not change.**
No program can do this step for you, and that is the point of Apple's design.

If it says "Your system did not boot into the correct recoveryOS" or "did not boot in One True
RecoveryOS (1TR) mode", the button was released too early or pressed twice: follow the text on
the screen (it shuts down; hold the button in one continuous press and choose SiliconForest again).

## 5. The first start

After step 5 the Mac starts SiliconForest by itself. On the one M1 that runs it, a start looks
like this: the SiliconForest mark on black for a few seconds while the boot stages run, then the
desktop about ten seconds later, and Wi-Fi about fifteen seconds after that. The first start of a
fresh install also sets up the Wi-Fi firmware and your account; what it asks is described in the
release notes of the release you installed (that first-start setup is part of the release image,
which is still being built).

If instead you see a log with "SiliconForest: stopped (reason)" or the mark stays for more than a
minute: hold the power button until the Mac is off, then section 6 (start macOS) and section 11.
Nothing on the disk was changed by that.

## 6. Choosing between macOS and SiliconForest

**Make macOS the default again** right after the first start (SiliconForest cannot change the
default itself): start macOS (below), then System Settings > General > Startup Disk > choose macOS,
or in the startup picker select macOS, hold the Option key and click "Always Use".

**Choosing at each start:** shut down, then press and hold the power button until "Loading startup
options…"; choose SiliconForest or macOS. A plain press starts the default (macOS).

## 7. Wi-Fi and Bluetooth firmware

The Wi-Fi and Bluetooth chips need Apple's firmware. SiliconForest does not distribute it. The
installer takes it, as the Asahi Linux installer does, from Apple's recovery image for your Mac
model (downloaded from Apple during step 4), and puts it inside SiliconForest's root, where the
first start unpacks it. You do not have to do anything. To join a network, use SiliconForest's
Wi-Fi settings (see the release notes).

## 8. Your own Mac applications

Some SiliconForest work runs Apple's own applications (Terminal, Activity Monitor). SiliconForest
does not include or distribute any Apple application, and the installer copies none. If you want
to use your own copies, a helper to copy them from your macOS into SiliconForest over the network
is planned (not written yet); whether you may run them there is between you and Apple's licence.

## 9. Updating

    curl -fsSL https://raw.githubusercontent.com/chriskearney/siliconforest/main/install.sh | sh -s -- --update

replaces SiliconForest's boot files (`sf/boot.bin`, `sf/kernel.bin`) on SFBOOT with the newest
release's, keeps the previous ones as `.old`, and changes nothing else; no recovery step is needed.
Updating the root filesystem in place is not available yet: for a new root, uninstall and install
again (your files in SiliconForest are lost; copy them off first). A release that needs a new first
boot stage says so and needs the recovery step again.

## 10. Uninstalling and getting the space back

1. Make macOS the startup disk (section 6). The uninstaller refuses while SiliconForest is.
2. In macOS:

       curl -fsSL https://raw.githubusercontent.com/chriskearney/siliconforest/main/install.sh | sh -s -- --uninstall

   It lists what it will delete (the SiliconForest container, SFBOOT, the root partition) and that
   it gives the space back to macOS, asks you to type "uninstall", then your password.
3. It deletes the three partitions and grows macOS's container back over the space. If another
   partition lies between macOS and the freed space, the space stays free and it says so.

Everything on SiliconForest's root is lost. The boot policy that step 5 created stays behind,
unused, in a small Apple system area; that is harmless and is what the Asahi project documents too.

Without the installer (if it cannot be downloaded), the same by hand, in Terminal, after checking
each identifier in `diskutil list` (a wrong identifier can delete macOS: if unsure, stop):

    diskutil apfs deleteContainer <the 2.5 GB container whose volume is SiliconForest>
    diskutil eraseVolume free free <the SFBOOT partition>
    diskutil eraseVolume free free <the partition after it>
    diskutil apfs resizeContainer <macOS's partition, usually disk0s2> 0

## 11. What can go wrong, and the way back

| What happens | What it means | What to do |
|---|---|---|
| The installer stops with `NO …` or "Nothing was changed" | a check failed before any change | do what the line says |
| "The disk changed between the plan you confirmed and now" | something else changed the disk | run the installer again |
| The resize fails | usually existing damage in the APFS filesystem | Disk Utility > First Aid on the macOS volume (from macOS Recovery if needed), then again |
| The installer is interrupted (power, Ctrl-C) after it started changing | some pieces may exist | run it again: it finds the incomplete installation and offers `--uninstall`, which removes exactly those pieces; then install again. The journal is in `/var/db/siliconforest-installer/` |
| The recovery step (5) went wrong or was skipped | SiliconForest is the startup disk but cannot start yet | hold the power button, choose macOS, and either repeat step 5 or uninstall |
| SiliconForest stops at start ("SiliconForest: stopped") or shows a frozen screen | it refused to start or hung; nothing is written | hold the power button until off, start macOS (section 6) |
| "macOS needs to be reinstalled" or a start loop after step 5 | the recovery step was not done in the right mode | shut down fully; hold the power button; start macOS; repeat step 5 |

**The Mac's own recovery always remains.** Apple silicon Macs keep a system recovery (and a
fallback copy) in their own containers, which the installer does not touch. Holding the power
button always reaches the startup picker, and from there macOS, its recovery and its Disk Utility.

**DFU restore** is Apple's last resort: from a second Mac, Apple Configurator reinstalls the
firmware and macOS and **erases the whole disk**. SiliconForest's installer never does it and never
needs you to; nothing in this process puts a Mac in a state that only DFU can fix, as far as the
Asahi project's years of installs and our one machine show. If you ever needed it, your backup is
what brings your files back.

## 12. Not supported (honest list)

- Any Mac but the 13-inch M1 MacBook Pro (2020); macOS older than 13.5 or newer than 26.
- Installing to an external disk; installing twice on one Mac; installing when macOS was started
  from an external disk.
- Updating SiliconForest's root in place (uninstall and reinstall instead).
- FileVault while it is still encrypting or decrypting (wait until it finishes). FileVault on is
  fine; SiliconForest's own root is not encrypted.
- Hardware SiliconForest does not drive yet: see the README's status section (sleep, Bluetooth,
  Thunderbolt and others are work in progress).
- Running SiliconForest as the default system (it is opt-in at each start; see the decision in
  `docs/roadmap/issues/SF-AJ-installer.md`).

## 13. Other Macs

The installer's list of Macs is data (`install/models.tsv`). A Mac gets a line marked supported
when SiliconForest's kernel, device tree handling and boot stages have been brought up and started
on that model, its storage driver's write fence has been proven there, one install and one
uninstall have been done on it by someone able to recover it, and the macOS firmware version its
drivers expect is recorded. Until then the installer refuses it by name.

## 14. Credits

The disk work of this installer is the **Asahi Linux installer**
(https://github.com/AsahiLinux/asahi-installer, MIT, "Copyright (c) 2021 The Asahi Linux
contributors"), version 0.9.2, used unmodified as the installer's engine: the stub volume, the
partitions, the firmware collection, the boot object and the recovery step are its code and its
words. SiliconForest's own part decides, shows, asks and checks (`install/`). The idea of driving a
pinned Asahi engine with a plan bound to the disk layout, and many lessons, come from **Omacom**'s
installer for Omarchy on Apple silicon (https://github.com/omacom/omarchy-mac-installer, MIT). The
first boot stage is **m1n1** by the Asahi Linux contributors. The comparison and what we took from
each is in `docs/roadmap/issues/SF-AJ-installer.md`.
