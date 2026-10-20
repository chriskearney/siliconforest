# Attended early-loader Recovery pilot

This is the first owner-attended J516S migration to the neutral early m1n1 splash. It is separate from Linux releases and the public installation catalog. The candidate has source/build comparisons and mocked-interface host tests; it has not yet passed a native Recovery migration or a hardware boot. Do not describe it as qualified until that evidence exists.

The files must already be staged on the intended Mac's EFI partition by the maintainer. The launcher downloads no boot images. It finds exactly one staged helper with its pinned SHA-256, then that helper verifies its private per-Mac metadata and both images. No Mac UUIDs, original images, owner credentials or keys are included in the public launcher.

Shut down with the Linux installation as the default Apple startup OS. Hold Power continuously to reach startup options, select Options, and open Utilities → Terminal. Run:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/iconidentify/siliconforest/recovery/start.sh)
```

Use process substitution, not `curl | bash`: stdin must remain attached to Terminal for confirmation and Apple's own owner-authentication prompt. The script verifies paired 1TR before proceeding. If it refuses anything, keep Recovery open and inspect the failure; do not work around a guard or run a general OS installer.

Before invoking `kmutil`, the helper matches the live Linux volume-group and EFI identities, identifies the APFS System and Preboot volumes by their roles, proves that the preserved raw original loader is present in the current custom image, validates the original loader's exported version and exact chainload variables, copies and verifies both original images, and saves policy diagnostics and a restoration script. The restore script uses the original System volume's UUID and its own current location, so changing Recovery mount names does not redirect it.

The only policy-writing operation is Apple's `kmutil configure-boot`, targeting that Linux System volume, with native owner authentication. There is no SIP command, security-level change, firmware update, password capture, or automatic reboot. Existing kernel, UKI, stage 2, menu and recovery image bytes are checked before and after. If installation fails or its output cannot be verified, leave Recovery open; the printed backup contains `restore.sh` to reinstall the preserved raw original through `kmutil`.

After a successful install, restart into Linux. Verify the newly exported stage-1 identity, the absence of an OS log-buffer overlap, the matched stage-2 composition, hardware OpenGL/Vulkan readback and the desktop. A successful `kmutil` exit is not a successful hardware boot. No rebooted rollback test is claimed by this source publication.

Host checks:

```sh
python3 -m unittest discover -s tests -p 'test_stage1_*.py' -v
bash -n start.sh
bash -n scripts/stage1-recovery-prepare.sh
```

The fixture replaces only macOS interfaces, the absolute PlistBuddy executable path and test-specific metadata digests. These tests exercise the real script branches and CLI arguments on disposable files; they do not validate the native Apple interfaces. The staged helper is the public preparation template with its metadata digest filled in. The raw neutral candidate is `iconidentify/siliconforest-m1n1` commit `eb01829bb8f276a07fa5151f18c6754ecb64e53b`, based on public Asahi commit `06a4601a351ebfd1abb6abba9a44c34e40d94776`, with only the three fixed-size logo objects changed at runtime.

Interface references: [m1n1 installation and stage-1 variables](https://asahilinux.org/docs/sw/m1n1-user-guide/), Asahi installer [paired Recovery checks](https://github.com/AsahiLinux/asahi-installer/blob/main/src/step2/step2.sh), [volume roles and custom-image location](https://github.com/AsahiLinux/asahi-installer/blob/main/src/osenum.py), and [diskutil interface](https://github.com/AsahiLinux/asahi-installer/blob/main/src/diskutil.py). Original authorship and licensing remain with those projects.
