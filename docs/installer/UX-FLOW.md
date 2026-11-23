<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 Chris Kearney and the SiliconForest contributors -->

# SiliconForest Installer: every screen

Companion to [`DESIGN.md`](DESIGN.md) and [`VISUAL-DESIGN.md`](VISUAL-DESIGN.md). This is the proposed copy. It moves into `SFCopy` as the one source of strings.

## Voice

- **Calm, exact, short.** One idea per screen.
- **Say what happens to the person's Mac and files**, in their terms. "macOS will have 312 GB", not "shrink disk0s2".
- **Never say "Oops", "Something went wrong" or "Please wait".** Say what happened and what to do.
- **Buttons name the action.** "Install SiliconForest", never "OK".
- **The way back is always visible.**
- **Never claim more than we know.** "No changes were made" appears only when the journal proves it.

## Layout of every screen

```
┌──────────────────────────────────────────────────────────────┐
│  ▲ SiliconForest                              ● ● ● ○ ○ ○ ○  │  mark, step dots
│                                                              │
│                                                              │
│        Large statement.                                      │
│        One or two supporting sentences.                      │
│                                                              │
│        [ the content for this step ]                         │
│                                                              │
│                                                              │
│  Details                                 Back   [ Continue ] │
└──────────────────────────────────────────────────────────────┘
```

Step dots: **Check · Prepare · Space · Review · Install · Recovery · Finish**.

---

## Part 1. Install, in macOS

### 1. Welcome

> # SiliconForest
> **A new operating system for your Mac, right beside macOS.**
>
> macOS and your files stay where they are. You choose which one to start, every time you turn on your Mac.

- Primary: **Get Started**
- Secondary: **What is SiliconForest?** (sheet), **Remove SiliconForest…** (only if installed)
- Footer: `MacBook Pro (13-inch, M1, 2020) · macOS 15.5`

*Motion:* the mark draws itself, trace by trace, then the vias light. The forest fades in behind it. On first paint only.

**If launched from the disk image:**

> ### Move to Applications first
> SiliconForest Installer needs to run from your Applications folder.
>
> **Move and Reopen** · Quit

### 2. Compatibility check

> # Checking your Mac
> This doesn't change anything.

A live checklist. Each row resolves in turn, with a small via that fills when it passes.

| Row | Passing text |
|---|---|
| This Mac | MacBook Pro (13-inch, M1, 2020) is supported |
| macOS | macOS 15.5 is supported |
| Startup firmware | Up to date |
| Your account | Chris is an administrator |
| FileVault | On. That's fine |
| Disk | Healthy layout, 494 GB |
| Free space | Enough room for SiliconForest |
| Power | Connected |
| Internet | Connected |

All pass:

> # Your Mac is ready

**Continue** is enabled.

#### Blocked variants

Each replaces the headline. Rows that passed stay visible.

| Case | Headline | Body | Actions |
|---|---|---|---|
| Unsupported Mac | **This Mac isn't supported yet** | SiliconForest runs on MacBook Pro (13-inch, M1, 2020). Each Mac is added after it has been tested on real hardware. | See Supported Macs · Quit |
| macOS too old | **Update macOS first** | SiliconForest needs macOS 13.5 or later. You have macOS 13.2. | Open Software Update · Check Again |
| macOS too new | **macOS 27 isn't tested yet** | Resizing the disk on macOS 27 has failed for others, so the installer won't risk it. Your Mac hasn't been changed. | Learn More · Quit |
| Not admin | **An administrator is needed** | Sign in with an administrator account and open the installer again. | Quit |
| Remote session | **Run this at the Mac** | Apple requires someone at the Mac for this. | Quit |
| FileVault converting | **FileVault is still working** | Wait for encryption to finish. It's 62% done. | Check Again |
| Locked volume | **A volume is locked** | "Archive" must be unlocked before the disk can be resized. | Open Disk Utility · Check Again |
| No space | **Not enough free space** | SiliconForest needs at least 11 GB, and macOS must keep 38 GB. Free up **9.2 GB**, then check again. | Open Storage Settings · Check Again |
| Snapshots hold space | **Time Machine is holding 41 GB** | Local snapshots are limiting how far macOS can shrink. They're safe to remove if your backup is current. | Remove Local Snapshots… · Check Again |
| Update pending | **A macOS update is waiting** | Finish or dismiss it before installing. | Open Software Update · Check Again |
| Hand-made install | **SiliconForest is already here, but not from this installer** | This installer won't change an installation it didn't create. Your systems are untouched. | Learn More · Quit |
| Unfinished install | **Pick up where you left off** | An earlier installation stopped at "Writing SiliconForest". | Continue · Undo It |
| Awaiting recovery | **One step left, in Recovery** | Your Mac is ready for the final step. | Show Me How |
| Already installed | **SiliconForest is installed** | Version 0.3 on "SiliconForest". | Update · Remove… · Quit |

### 3. Before You Begin

> # Before you begin
> Here's exactly what the installer will and won't do.

Two columns:

| What changes | What doesn't |
|---|---|
| macOS's partition gets smaller | Your files and apps |
| Three new partitions for SiliconForest | macOS's security settings |
| SiliconForest appears at startup | Any other system on this Mac |

Then:

> **Back up first.** Resizing a disk is safe when it works, but a power cut or existing disk damage can cause data loss.
>
> Last Time Machine backup: **Today, 9:42 AM** on "Basecamp"

- Checkbox: **☐ I have a current backup of this Mac**
- If no backup is known: **Open Time Machine Settings**
- Disclosure, **About security:**

> SiliconForest uses a custom kernel, so its startup security must be set to Permissive. **This applies only to SiliconForest. macOS keeps its own security level.** Apple doesn't provide or support custom kernels.

- Primary: **Continue** (requires the checkbox)

### 4. Choose Your Space

The hero screen. See the [mockup](mockups/choose-space.svg).

> # Choose your space
> Drag to decide how much goes to SiliconForest. You can remove it later and get the space back.

```
  macOS                                                   SiliconForest
  394 GB                                                         100 GB

  ████████████▒▒▒▒▒▒▒▒▒▒▒░░░░░░░░░░░░░░◉▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
  used 148 GB   snapshots 6   free 240 │                  new 100 GB
                                       └ drag
  Keeps 240 GB free in macOS                      [ 100 ] GB  – +

  ( Recommended )  ( Half )  ( Minimum )  ( Maximum )
```

- The bar shows real proportions: used, snapshots, free, and SiliconForest's new space.
- **Drag**, **type a size**, use **− / +**, use **arrow keys** (1 GB; Shift for 10 GB), or pick a **preset**. All stay in sync.
- As you drag, numbers roll. A trace from the handle to each label stays attached.
- **At the limit** the handle stops with a soft bump, and one line explains why:
  - *macOS needs to keep 38 GB free for updates.*
  - *Time Machine snapshots are holding 41 GB.* **Manage…**
  - *SiliconForest needs at least 11 GB.*
- Below 40 GB, a quiet note: *That's enough to start, but not for much else.*
- With a fixed-size release image: the handle is locked. *This release uses a fixed 7.3 GB. Larger installations are coming.*
- Disclosure, **Show partition details:** the exact before and after table.
- VoiceOver: "SiliconForest size, 100 gigabytes. macOS keeps 394 gigabytes. Adjustable."

Primary: **Continue**

### 5. Options

> # A few choices
> The defaults are good. Change them only if you want to.

| Option | Default | Help |
|---|---|---|
| **Name at startup** | SiliconForest | The name in the startup picker |
| **After setup** | Start SiliconForest once, keep your current startup system | If the first start has any trouble, your Mac goes back to the system it starts today |
| | ○ Make SiliconForest the default after it starts successfully | |

Advanced (collapsed):

| Option | Default |
|---|---|
| Release channel | Stable |
| Keep the downloaded files after install | Off |
| Use a local release folder (developer builds only) | Off |

### 6. Review

The point of no return gets its own screen.

> # Review and install
> Nothing has changed yet.

A **before and after** pair of disk bars. The bar from the previous screen moves here in one continuous motion.

```
Now    ████████████████████████████████████████████████████████
After  ████████████████████████████████████░░░░░░░░░░▓▓▓▓▓▓▓▓▓▓
```

| The installer will | |
|---|---|
| Shrink macOS | 494 GB → 394 GB (keeps 240 GB free) |
| Add SiliconForest | 100 GB in three partitions |
| Download | 3.4 GB from SiliconForest, 0.7 GB from Apple |
| Time | About 25 minutes, then one step from you |

> **You'll need to do one thing yourself.** After this, you'll restart into Recovery and approve SiliconForest with your password. We'll show you how.

- Link: **Show What Would Happen** (the dry run's exact command list, plain text, copyable)
- Buttons: **Back** · **Install SiliconForest** (no default key; Return does nothing)

### 7. Approve the Installer

> # Allow the installer to make changes
> macOS will ask you to approve a helper. It can only do the steps you just reviewed, and it's removed when the installation finishes.

1. Click **Open Login Items**.
2. Turn on **SiliconForest Installer**.
3. Come back. We'll continue automatically.

A small animated illustration of the toggle. The screen advances the moment status is enabled.

### 8. Preparing

> # Getting everything ready
> **Your disk hasn't been touched.** You can still cancel.

```
✓  SiliconForest 0.3            3.4 GB   verified
●  Apple startup files          412 of 720 MB   4 min left
○  Checking every file
```

- **Cancel** stays available here.
- On metered networks: *You're on a personal hotspot. This will use about 4 GB.* **Continue** · **Wait**
- Offline: *Waiting for the internet. Downloads will resume on their own.*

### 9. Installing

> # Installing SiliconForest
> Keep your Mac open and plugged in.

The forest brightens toward dawn as work completes. Named phases with truthful progress:

```
✓  Making room                      Done in 3 min
●  Preparing the startup volume     612 of 720 MB
○  Writing SiliconForest
○  Checking what was written
○  Adding drivers for your Mac
○  Final preparations
                                    About 14 minutes left
```

- **There is no Cancel** while a step can't be safely interrupted. The reason is one click away: **Why can't I stop this?**
- **Stall honesty**, on the resize: *macOS is still working on this. It can take a long time and may look stuck. Don't shut down.*
- **Show Details** reveals a live, monospaced log.
- If the power cable is pulled: *Plug your Mac back in.* Long steps continue only while the battery is above 30%.

### 10. Get Ready for Recovery

Before shutting down, the installer teaches the one thing it can't do.

> # One last step, and it's yours
> Apple requires you to approve a new operating system in person. It takes about two minutes.

An animated keyboard shows the Touch ID key being pressed and held, with a timer ring.

```
1  Your Mac will shut down.
2  Wait for the screen to go dark, then 25 more seconds.
3  Press and HOLD the power button until you see "Loading startup options".
4  Choose SiliconForest, then click Continue.
5  Enter your Mac password when asked.
```

- **Practice** runs the hold animation and lets you press Space to feel the timing.
- **Save These Steps** exports a one-page PDF. **Show on iPhone** displays a QR code, once a public help page exists.
- Note: *If you let go too early, nothing is harmed. The screen will tell you, and you can try again.*
- Primary: **Shut Down** (no default key)
- Secondary: **Not Now** (the app remembers, and returns here)

---

## Part 2. In recoveryOS

The recovery app can use AppKit only. It shows the same forest as a still image, with the same type.

### R1. Welcome back

> # Finish installing SiliconForest
> Enter the password for **Chris** to allow SiliconForest to start on this Mac.
>
> This lowers security **for SiliconForest only**. macOS isn't affected.

- Password field. **Allow SiliconForest**
- Utilities menu: **Terminal**, **Show Details**, **Shut Down**

### R2. Working

> # Setting up SiliconForest

```
✓  Checking this recovery system
●  Allowing SiliconForest to start
○  Installing the startup software
○  Finishing up
```

### R3. Ready

> # All set
> Your Mac will now start SiliconForest for the first time. If anything goes wrong, turn it off and on and you'll be back in {current startup system}.

**Restart** (auto after 15 seconds, with a visible countdown and **Wait**)

*This copy assumes the one-shot first boot (spike S5). If that is unavailable, the second sentence becomes: "If it doesn't start, hold the power button until the Mac turns off, then hold it again and choose macOS."*

### Recovery failures

| Case | Headline | Body | Actions |
|---|---|---|---|
| Wrong password | **That password didn't work** | Use the password for an administrator of your macOS. | Try Again |
| Wrong recovery | **Almost: this is the wrong recovery** | Your Mac needs to start from SiliconForest's recovery. We'll set that and shut down. Then hold the power button again until "Loading startup options". | Shut Down |
| Not held (not 1TR) | **The button wasn't held long enough** | Shut down, then press and hold in one continuous press. Don't tap first. | Shut Down |
| Owner not found | **Your account can't approve this** | macOS may have been reinstalled since setup. Start macOS and open the installer to refresh it. | Shut Down |
| Apple tool error | **Apple's tool stopped: `<real message>`** | `<specific guidance>`. Your macOS isn't affected. | Try Again · Show Details |
| App can't start | *(automatic)* | Terminal opens with the same steps in plain text. | Press Return |

---

## Part 3. Back in macOS

The app reopens at the next macOS login, or when the user opens it, and reads the boot receipt. If another system is the default, the user starts macOS from the picker to see this.

### F1. Installed

> # SiliconForest is installed
> It started successfully on this Mac.
>
> **To switch:** shut down, then hold the power button and choose.

The forest has reached full dawn. This is the only screen with a celebration: the vias light outward along the traces, once.

- **Done**
- Optional: **Make SiliconForest the Default**
- Quiet: *You can remove SiliconForest any time from this app.*

### F2. Started but didn't finish

> # SiliconForest started, but didn't finish
> It got as far as **starting system services**. Your Mac and macOS are fine.

**Try Again** · **Export Diagnostics** · **Remove SiliconForest…**

### F3. Didn't start

> # SiliconForest didn't start
> Your Mac went back to {current startup system} safely. Nothing in macOS was changed.

**Try Again** · **Export Diagnostics** · **Remove SiliconForest…**

---

## Part 4. Remove SiliconForest

### U1. What will be removed

> # Remove SiliconForest
> This deletes SiliconForest and everything stored in it, then gives the space back to macOS.

```
Now    ██████████████████████████████████████▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
After  ███████████████████████████████████████████████████████
```

| Removed | Kept |
|---|---|
| SiliconForest (100 GB) | macOS and your files |
| **All your files in SiliconForest** | Any other system on this Mac |

macOS grows back to 494 GB.

If space can't be returned: *Another partition sits between macOS and this space, so it will stay free for now.*

### U2. Confirm

> ### Type **SiliconForest** to confirm

Text field. **Remove SiliconForest** (destructive style, disabled until the text matches, no default key). **Cancel.**

### U3. Removing

```
✓  Making macOS the startup disk
●  Removing SiliconForest
○  Returning the space to macOS
○  Checking the result
```

### U4. Removed

> # SiliconForest has been removed
> macOS is back to 494 GB. A small, unused security record stays in Apple's system area. It's harmless.

**Done**

### Removal failures

| Case | Headline | Actions |
|---|---|---|
| Can't prove it's ours | **This doesn't look like an installation we made** · Nothing was removed. | Learn More |
| Startup disk can't be set | **macOS couldn't be set as the startup disk** · Nothing was removed. | Try Again |
| Stopped partway | **Removal stopped partway** · Here's what's done and what's left. | Continue Removal · Export Diagnostics |
| Grow failed | **SiliconForest is gone, but the space wasn't returned** · Your files are safe. | Try Again · First Aid Steps |

---

## Part 5. Failure and rollback

One screen template. It always answers **What happened, What it means for your Mac, What to do.**

### E1. Stopped, nothing changed

> # The installation stopped
> **No changes were made to your disk.**
>
> The download from Apple failed: connection timed out.

**Try Again** · Quit

### E2. Stopped, can be undone

> # The installation stopped
> macOS and your files are fine. The installer had made some changes, and it can undo them.
>
> Could not create the startup volume: `<real Apple error>`

**Undo Changes** · **Try Again** · Export Diagnostics

### E3. Undoing

> # Putting things back

```
✓  Removing the partial installation
●  Returning space to macOS
○  Checking the result
```

### E4. Undone

> # Everything is back as it was
> Your disk matches how it was before the installation.

**Done**

### E5. Needs attention

> # This needs your attention
> Your disk isn't in the state the installer expected, so it has stopped rather than guess. **macOS should still start normally.** Don't erase anything.
>
> **Export Diagnostics** and open an issue. We'll help you sort it out.

**Export Diagnostics** · **Show Details**

### E6. Resize still running after relaunch

> # macOS is still resizing your disk
> The installer reconnected to it. Don't shut down.

### E7. Disk needs repair

> # macOS found a problem with your disk
> This was there before the installer ran. Repair it from Recovery with First Aid, then try again. **Nothing was changed.**

**Show Me How** · Export Diagnostics

### Diagnostics sheet

> ### Export diagnostics
> A file you can read first and choose to share. It contains no passwords, serial numbers, names or personal files, and nothing is sent automatically.

File list, **Save…**, Cancel.
