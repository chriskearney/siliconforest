# Private packet link transport

P8 stopped at PerformanceAnalysis despite the earlier p0/QTP inventory resolving
both imports. The fresh Preview overlay's target ended at 100 bytes; the complete
113-byte target was intact in the original packet, its PAX linkpath and the
local source tree. QTP's framework, Current -> A, versioned ID, compatibility,
exports and backing bytes were valid. This was a later staging defect, not a
version mismatch or missing QTP implementation.

A controlled native M1 fixture reproduced guest tar truncating that PAX target
to 100 bytes. Direct OS link creation preserved all 113. The focused arm64
`performance-probe.nix` consumer rejected the broken path, then loaded the exact
existing open QTP provider and resolved Start/End. It observed zero recording
tokens and return from End: no telemetry/recording support is claimed. The
packaged open QTP Source/Unavailable.c establishes its two-pointer boundary;
Finch SmallPrivate's separate three-pointer source was not substituted.
Only the observed owned-prefix link was atomically replaced. QTP stayed intact.

Read-only comparison of all 42 packet symlinks found eight exact 100-byte cuts,
all with valid complete QTP targets: CoreFoundation, DeveloperToolsSupport,
FeatureFlags, MediaRemote, MobileAsset, MonitorPanel, PerformanceAnalysis and
PhotosFormats. The seven other active links were left untouched, pending each
observed gate and an independently validated provider.

For FUTURE fresh packets, replace native guest tar extraction with:

```sh
python3 unpack-private-stage.py packet.tar.gz --root NEW_OWNED_STAGE
```

The archive may instead be stdin (`-`). The helper refuses a nonempty root,
reads complete PAX metadata with Python, extracts files before creating links
through the OS API, then compares every declared file digest and every literal
`readlink` string with SHA256SUMS.json. It never repairs an active prefix and
never executes the app. Archive names cannot escape the new root or descend
through an archived symlink. Target existence/exports/ABI remain separate proof.

The original private packet round-trip passed all 195 regular-file digests and
42 exact link strings on the builder; attempting it again refused the populated
root. The actual M1 stdin extractor passed a separate tiny fixture with the full
113-byte target. These are transport checks, not application UI acceptance.

Hardlink sources must be already-extracted regular archive members, or members
of a resolved internal hardlink chain. Chains are resolved before creating any
symlinks; cycles, nonmembers and symlink sources are rejected. SHA256SUMS.json
itself must be a regular archive member, not a symlink or hardlink. Manifest
file entries must name verified regular members, preventing lookup through an
unrelated staged alias.

Reviewed fixtures passed on both builder and M1: forward internal hardlink
chain with the 113-byte link succeeds; hardlink-to-symlink, nonmember, cycle,
symlink manifest and hardlink manifest are rejected. The original packet still
passes all 195 regular-file digests and 42 literal targets. The private future
harness now invokes this extractor instead of native tar; it independently
rejects the retained p0 and active run roots and performs no app launch.
