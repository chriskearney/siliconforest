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

On J516S/14.7 with kernel `7560c8b4747f`, the keyboard's PWM LED control passed
from the active desktop session (102 → 90 → 102 out of 255). This kernel has no
screen backlight device on that firmware path. The normal display driver needs
the panel-brightness support described in
[public linux-aurora PR148](https://github.com/omacom/linux-aurora/pull/148).
That PR also includes GPU and HDMI audio changes; those are separate from this
brightness task.

M1/M2 laptop device trees already describe the keyboard PWM LED and the panel
brightness ceiling, and the release configuration enables the required PWM,
LED and backlight drivers. Their source support does not substitute for checking
each running machine. Other firmware paths, including M3 Air 26.6.2, need their
own hardware results.
