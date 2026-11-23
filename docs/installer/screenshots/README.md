# Installer screenshots

Rendered offscreen from the app's own views (`SFInstaller --snapshot DIR --sizes 1280x800@2,1512x982@1`,
see `installer/mac/README.md`), dry run on the simulated 13-inch M1 MacBook Pro (J293), the Grove
frozen at one moment. No window was opened to make them. The layout, type, colours and Grove artwork are
ours; the small symbols (checkmarks, chevrons, the lock and so on) are Apple SF Symbols, drawn by macOS at
render time and not shipped in this repository.

- `2560x1600/`: the 13-inch M1's panel (1280×800 pt @2x), key screens.
- `1512x982/`: every state, dark and light.

Large displays keep the same centred content column (at most 880 pt), so a 2560×1600-point screen shows the
same composition with more forest on both sides; that size is checked when the layout changes but not committed.

| File | Screen (docs/installer/UX-FLOW.md) |
|---|---|
| 01-welcome | 1. Welcome |
| 02-check, 02b-check-running | 2. Compatibility check (all pass; resolving) |
| 02c-check-no-space, 02d-check-hand-made | Blocked variants: not enough space; hand-made install (sf.unproven) |
| 03-before-you-begin | 3. Before you begin (About security open) |
| 04-space, 04b-space-limit | 4. Choose your space (handle active; at the macOS limit with details) |
| 05-options | 5. A few choices |
| 06-review, 06b-what-would-happen | 6. Review and install; the dry run's command list |
| 07-approve | 7. Allow the installer to make changes |
| 08-preparing | 8. Getting everything ready (no disk writes yet) |
| 09-installing, 09b-installing-details, 09c-installing-resize | 9. Installing (dawn rising; Details; during the resize) |
| 10-recovery | 10. One last step (Recovery handoff) |
| 11-in-recovery, 11b-in-recovery-working | Part 2, R1/R2 (simulated recoveryOS) |
| 12-finish | Part 3, F1 Installed (the Clearing) |
| 13-remove, 14-remove-confirm, 15-removing, 16-removed | Part 4, U1–U4 |
| 17-stopped-can-undo, 17b-undone, 17c-stopped-nothing-changed | Part 5, E2, E4, E1 |
| 18-quit-confirm | Quit during a step |
| 19-recovery-password, 19-recovery-working, 19-recovery-failed | SFRecovery in recoveryOS (AppKit; DESIGN §7.4), rendered with `SFRecovery --snapshot` |
