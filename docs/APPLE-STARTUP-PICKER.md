# Apple startup-picker icon and name (attended M3 Pro pilot)

This changes the icon and display name of the existing J516S Linux startup
volume in Apple's Power-button picker. It is separate from Limine, Plymouth
and the two m1n1 stages. The exact per-Mac capsule must be staged by the
maintainer before use. This initial updater has host tests with mocked Apple
interfaces; actual Recovery execution and the visible result remain to be
verified on the owner's Mac. It is not an all-Mac installer.

## Run on the staged M3 Pro

1. Shut down. Hold Power to reach startup options, select **Options**, then open
   **Utilities → Terminal**, as for the earlier attended Recovery step.
2. Run:

   ```bash
   bash <(curl -fsSL https://raw.githubusercontent.com/iconidentify/siliconforest/picker1/picker.sh)
   ```

3. Read the identified startup volume and printed backup path. Type `yes` to
   replace the existing custom icon and set the System-volume display name to
   **SiliconForest Linux**. The terminal's stdin stays attached for this prompt.
4. After success, shut down and hold Power again. Check the SiliconForest icon
   and name, then start Linux. The updater never reboots automatically.

For a read-only inspection, append `--inspect` to the command. If anything is
refused, keep Recovery open and report the exact message. Do not reinstall the
OS or change a security setting to work around the refusal.

The launcher and checksum executable use the same authenticated HTTPS origin.
The executable uses Go's SHA-256 implementation with known-answer tests; no
OpenSSL, Perl, Python, `shasum` or `cmp` is required in Recovery. Pins cover the
utility, updater, icon and private metadata. The staged helper verifies the
paired Recovery, EFI identity, unique APFS volume group, System role, durable
System-volume UUID, and current stage-2 digest before any metadata change.
All remaining command dependencies are checked up front.

## Scope and recovery

The helper preserves the original icon, mode and name on the EFI partition,
checks the backup, prints a standalone `restore.sh`, and waits for confirmation.
It atomically replaces `.VolumeIcon.icns` and uses `diskutil renameVolume` only
on the identified System volume. The existing root directory and its custom
icon flags are retained. If no custom icon already exists, it refuses instead
of guessing extended attributes. It re-queries the volume through its UUID
when a rename changes its mount path. Rename/replacement failures attempt to
restore the original icon and name; incomplete recovery leaves the originals
and an explicit status for inspection.

Before and after, it verifies that the Linux UKIs, Limine menu, stage 2, loader
backups, original raw stage 1, active custom image and policy hashes stay the
same. There is no `kmutil configure-boot`, `bless`, security-level change,
firmware update or OS reinstall. The Data volume is not renamed. No actual Mac
UUID, original icon, policy record or owner credential is published.

To undo, run the exact `bash .../restore.sh` command printed by the helper in
Recovery. It resolves the original System volume by UUID, checks the original
backup and refuses to overwrite independently changed artwork or names. It
restores only the icon and name, leaving later Linux kernel updates in place.
An interrupted operation may leave the capsule lock and requires inspection;
its already-printed backup remains available. Do not remove a lock blindly.

## Artwork and validation

The master SVG and ICNS are in `branding/apple-picker/`. Reproduce the icon on
the development host (resvg 0.48.1 required):

```sh
python3 scripts/build-apple-picker-icon.py --output /tmp/siliconforest-volume.icns
```

The file has PNG icon slots for 16, 32, 64, 128, 256, 512 and 1024 pixels. All
seven were independently decoded and compared to their source PNGs. Updating
this artwork requires a new pinned capsule and launcher; it does not require
rebuilding m1n1.

Host tests cover discovery, capsule pins, terminal confirmation, idempotence,
UUID/mount-name changes, backup corruption, failed/partial renames, an
unwritable icon slot, concurrent operations, independently changed icons,
later kernel updates and preservation of boot inputs. These do not substitute
for a native Recovery run, visual confirmation or a rebooted restoration test.

Interface references: Asahi's [stub installer and volume icon](https://github.com/AsahiLinux/asahi-installer/blob/main/src/stub.py)
and [startup volume name](https://asahilinux.org/docs/platform/dev-quickstart/).
