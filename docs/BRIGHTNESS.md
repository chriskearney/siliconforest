# Display and keyboard brightness

On Omarchy, use the brightness keys (F1/F2 on the built-in Mac keyboard) for
the focused display. Shift plus those keys adjusts the keyboard backlight;
Alt plus them makes smaller display adjustments. If the keyboard is configured
to emit ordinary function keys, hold Fn as well. Dedicated keyboard-light keys
also work where present. The current M3 Pro Chonkstep session has these bindings.

The equivalent commands, run from a terminal in the desktop session, are:

```sh
omarchy brightness display --monitor eDP-1 +5%
omarchy brightness display --monitor eDP-1 5%-
omarchy brightness keyboard up
omarchy brightness keyboard down
```

For an explicit keyboard level:

```sh
brightnessctl --device='*kbd_backlight*' set 40%
```

`apple-panel-bl` controls the built-in screen. External monitors use their own
DDC or Apple Display controls; a focused external monitor does not select the
built-in panel. The M1 13-inch MacBook Pro's Touch Bar has a separate backlight;
Omarchy prefers `apple-panel-bl` so screen controls do not dim the Touch Bar.

Brightness changes use logind's active desktop session permissions. An SSH
session may get `Operation not permitted` even when the same command and keys
work at the desktop. This does not call for world-writable sysfs files or
unrestricted sudo rules. systemd-backlight saves and restores keyboard levels.

## Hardware checks

Run the attended check from the desktop user's terminal:

```sh
python3 tests/hardware/brightness.py --exercise --output brightness.json
```

It briefly changes each available keyboard and internal-screen control, checks
driver readback, then restores the original level. It refuses to exercise a
screen reporting zero or an unknown initial brightness, and reports missing controls as a failure.
For a newly registered screen control whose inherited level is unknown, first
set a deliberate level from the desktop, for example
`omarchy brightness display --monitor eDP-1 40%`, then run the check.
Driver readback is separate from a person confirming visible light changes.
The check installs nothing and does not change keybindings or monitor modes.

J516S/14.7 uses kernel `54add20fd52e`, retaining `apple-panel-bl`
with a 500-nit ceiling on the normal T6030 display path. The keyboard remains
`white:kbd_backlight`, with 255 levels. On the tested desktop, screen updates
300 → 275 → 300 and keyboard updates 102 → 90 → 102 passed. Regular Omarchy
commands, including their OSD calls, also passed: screen 300 → 325 → 300 and
keyboard 102 → 127 → 102. Completed firmware presents include idle-frame updates,
with no refusals. [Hardware evidence and limits](../release/reports/20261018-j516s-brightness.json).

The loader's screen level is preserved until Linux receives a request. Before a
level is known, `brightness` shows an unsent 140-nit placeholder and
`actual_brightness` returns ENODATA. A systemd-backlight restore is a Linux
request; on the tested boot it restored 300 nits. This report verifies software
control and firmware completion, without claiming optical calibration or an
owner's visual confirmation.

The implementation adapts the brightness portion of
[public linux-aurora PR148](https://github.com/omacom/linux-aurora/pull/148),
with downstream changes for framebuffer lifetime, PM/unbind queue closure,
unknown-level reporting, and other-board isolation.
[Source review and tests](../release/source-reviews/20261018-brightness.json).

M1/M2 laptop device trees already describe the keyboard PWM LED and the panel
brightness ceiling, and the release configuration enables the required PWM,
LED and backlight drivers. Their source support does not substitute for checking
each running machine. Other firmware paths, including M3 Air 26.6.2, need their
own hardware results.

The PR148 rollout also exercised the M1 Air J313/13.5. Its keyboard control
passed. Panel requests produced monotonic actual readings (105 → 105,
210 → 223, 315 → 340, 400 → 421), and the original 302-requested/325-actual
pair was restored. The preceding kernel has the same offset. Exact readback
therefore fails the strict hardware helper: an actual value can even exceed the
420 maximum. This is a documented readback limitation, not an optical luminance
measurement. [Current Air evidence](../release/reports/20261018-j313-pr148.json).
