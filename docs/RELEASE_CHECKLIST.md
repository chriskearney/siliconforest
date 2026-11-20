# Release checklist: what stands between this repository and "public"

State: 17 November 2026, after the `release-prep` branch. **Route decided by the owner the same
day: this repository itself becomes public, with its history; there is no fresh repository.** Source: the open-source audit of
the same day (31 findings, numbered F1 to F31 below) and the work done since. The repository
is private; only the owner changes that.

"Owner" marks a decision only the owner can take. Effort is a rough estimate.
Nothing here is legal advice.

## Done on `release-prep`

| Item | Audit | What was done |
|---|---|---|
| Licence for our own code | F2 | `LICENSE-SILICONFOREST-MIT` (the MIT grant and the SiliconForest copyright notice; the root `LICENSE` is the mixed-licence notice), `LICENSES/` with every licence text in use and its source, `NOTICE` corrected, `LICENSE_STATUS.md` now a pointer |
| Outsider documentation | F9 | `README.md`, `CONTRIBUTING.md`, `SECURITY.md`, screenshots in `docs/images/` |
| Disk identifier in a test | F6 | the literal in `tests/test_m1_boot_install.py` is synthetic |
| Build output in the tree | F5 | `chonkstep-darwin/client-dmabuf/target*/` removed, ignored |
| Session links inside files | F10 (files) | removed from two `m1-touchbar` patches and one `m1-sound` commit text |
| Other vendors' screenshots | F4 | 107 capture images removed from the vendored Chonkstep copy |
| Personal address in files | F14 | the three vendored packaging files use the noreply address |
| Issue wording | | titles and bodies reviewed; see the record kept outside git (`runs/public/issue-edits.md`) |

| Continuous integration | F13 | the workflow passes on a source-only checkout: `tools/ci_check.py` runs `tools/check.py` unchanged and accepts exactly one known test that needs untracked build artefacts, reporting it as not run. Passed locally with clang and gcc; **not yet seen green on GitHub's runner** |

All of these are fixed **in the tree only**. Every one is still in the history of this
repository (see 2).

## Blockers

### 1. The old pull requests (F1). Owner; GitHub side. Cannot be fixed in the tree.
Pull requests 1 to 22 are from an earlier, unrelated project that used this repository (a
Linux installer). They stay visible as closed pull requests, and GitHub keeps
`refs/pull/N/head` for each (112 commits reachable only from them). **Three of them contain
`release/source-reviews/20261021-neo-candidate.json`, which holds the owner's personal-domain
email address.** Their titles, descriptions and comments were measured by the audit, not read.
- A repository owner cannot delete a pull request or its ref. Only GitHub Support can remove
  them (ask for the pull requests and their refs to be deleted because they expose personal
  data; say which three). Do this **before** the switch: once public, the refs can be
  fetched and cached by anyone and cannot be recalled.
- If Support does not act in time, the choice is to accept that address being public or to
  wait.
- Effort: one support request; days of waiting.

### 2. What becomes public with the history, and what can still be done. Owner / coordinator.
None of this can be changed by a commit. "Irreversible" means: once the repository is
public, assume it has been cloned.

| What | Where | What can be done on GitHub before the switch | After the switch |
|---|---|---|---|
| 22 old pull requests, three with a personal email in a file | pull requests, `refs/pull/*` | GitHub Support only (see 1) | irreversible |
| About 414 Actions runs, every recent one failed, with logs (runner paths and test output; the audit did not read them) | Actions tab | delete the runs (`gh run delete`, or the API in a loop; a coordinator task of minutes) or disable Actions until the first green run; logs also expire by retention | deletable at any time, but visible until deleted |
| A `Claude-Session:` link in 773 of 788 commit messages on `main`, and `Co-Authored-By: Claude` lines | history | nothing short of rewriting history (changes every commit id; the owner chose not to). The links open only for the account that owns the sessions (inferred, not tested from another account) | irreversible |
| 11 commits authored as `darwin-lab@localhost` | history | same | irreversible |
| The removed Cargo build output (491 files, about 110 MiB; 9 host ELF files and 1 Mach-O of our own build) | history; the repository is about 250 MiB | same; it costs clone size, nothing else known | irreversible |
| The removed capture images (107 files: Apple System 7.5.3 in Infinite Mac, OS/2 Warp, BeOS) | history | same. **This is the item to weigh**: other vendors' screenshots whose redistribution is not cleared stay fetchable from history | irreversible |
| The real partition GUID that was in `tests/test_m1_boot_install.py`, and the personal address in three vendored packaging files | history | same. The GUID identifies a partition on one disk and gives no access. The address is the same one as in 1 | irreversible |
| Branches on origin other than `main`: `pcie-wifi`, `sf-rename`, `sf-rename-audio`, `release-prep`, `ext4-fsck-clean`, `upstream-xnu-12377`, `upstream-20-5-oss`, `upstream-puredarwin-main` | branches | delete the merged or stale ones (`git push origin --delete <name>`; `sf-rename` equals `main`). Keep `ext4-fsck-clean` (unmerged fix, issue #61) and decide on `sf-rename-audio`. The `upstream-*` branches are PureDarwin's public history: harmless, but they make the repository look like a mirror; the audit recommends dropping them. Deleting a branch does not remove commits that other branches reach | deletable, but anything fetched meanwhile stays fetched |
| Issues 23 to 61 and their 101 comments | issues | titles and bodies were edited; comments left for the owner are listed in `runs/public/issue-edits.md` (not in git) | editable at any time; edit history of a comment stays visible to readers unless the revision is deleted |
| Repository description, topics, social preview | settings | set before the switch (proposal in the hand-back report) | editable |

Local only, never to be pushed: branches with 11 commits under another personal address
(F15). Push one branch by name, never `--all` or `--mirror`.

### 3. The vendored Chonkstep copy (F7, F18, F20, F31). Owner.
`integrations/siliconforest/chonkstep-darwin/desktop-shell/source/` is a full copy of
Chonkstep at one commit (about 4,000 files, a third of the tree), GPL-3.0-only, with 57 MiB
of benchmark evidence that names machines, and Bluetooth-style sample addresses that look
like fixtures but were not confirmed to be invented.
- Recommended by the audit: remove the copy, pin upstream Chonkstep by commit, keep the Darwin
  changes as a patch series with SPDX lines (only 2 of the 38 compositor patches carry a
  licence line today), and drop patches as upstream takes them.
- Until then the copy's tests that read the removed captures do not build.
- Effort: one to two days, plus the upstream merge on Chonkstep's side.

### 4. GPL-2.0 kernel extensions and the APSL kernel (F3). Owner; take advice.
About 350 files are GPL-2.0 ports of Linux drivers, built as kernel extensions against XNU's
interfaces and prelinked with XNU (APSL 2.0) into one kernel collection. The FSF lists
APSL 2.0 as a free licence that is not GPL-compatible. The question, stated and not answered
here: on what terms may a **built** collection or system image be distributed? Publishing
the sources side by side, each under its own licence with notices intact, is common practice.
- Related: about 77 files are dual-licensed (GPL-2.0 OR MIT / BSD) and could be taken under
  the permissive option, the Rust GPU driver among them; the desktop (GPL-3.0-only) links
  the APSL libSystem.
- Decision needed before any binary is published: source only, or images too; and if images,
  with which firmware and Apple-licensed parts left out.
- Effort: the decision; advice if wanted.

Notes added 19 November 2026, from the licence pass. Not legal advice. No decision
is recorded here.

- A PureDarwin maintainer asked the same distribution question on issue 23:
  https://github.com/chriskearney/siliconforest/issues/23#issuecomment-6984090313
- The FSF's licence list describes APSL 2.0 as a free software licence that is
  incompatible with the GPL: https://www.gnu.org/licenses/license-list.html#apsl2
  If that view applies to this kernel collection, distributing it may not be
  possible under both GPL-2.0-only and APSL-2.0 at once. Publishing the sources
  side by side, as the paragraph above calls common practice, is not by itself
  a statement that the combined binary may be shipped.
- The same list describes the Apache License 2.0 as incompatible with GPL version 2:
  https://www.gnu.org/licenses/license-list.html#apache2
  Finch is recorded as MIT OR Apache-2.0 (userspace frameworks). The GPL-2.0-only
  code identified in this tree is in kernel extensions. No build in that pass showed
  a Finch object linked into a GPL-2.0-only kext, and no file records a choice of
  Finch's MIT side or its Apache-2.0 side. A binary that takes the Apache-2.0 side
  together with GPL-2.0-only code is the same kind of open question.
- The GPL-3.0-only desktop linking the APSL libSystem, already noted above, is
  unanswered as well.

The MIT grant those notes used to sit beside is `LICENSE-SILICONFOREST-MIT`. The
root `LICENSE` is the mixed-licence notice. No recipe in this repository installs
the root `LICENSE` under the name `LICENSE.build-recipes`. `NOTICE` says the licence
texts are not yet installed beside `/usr/share/doc/siliconforest/NOTICE`. A release
recipe outside this tree that bundled the old root `LICENSE` as the MIT grant should
take `LICENSE-SILICONFOREST-MIT` for that grant and keep the root `LICENSE` as the
notice.

## High

### 5. Build reproducibility for outsiders (F8). Work.
32 recipes fetch from `file:///home/…` local clones; about 400 files name `/nix/store/<hash>`
paths; 99 tools or recipes read the untracked `artifacts/` or `private/`; there is no single
lock for the 25 source checkouts.
- To do: a `sources.lock` and fetch script; recipes that fetch by URL and hash; a build from a
  clean clone on a machine with none of the local directories; a QEMU boot of the result;
  a BUILDING and an INSTALL guide that are not written for one disk.
- Effort: one to two weeks. Until then the README says plainly that the system cannot be
  built from a clone.

### 6. Per-file headers (F24, F25, F26, F27). Work, with owner sign-off on the MIT tags.
- About 1,975 files say `SPDX-License-Identifier: MIT` with no copyright line (807 under
  `finch/`, 259 under `firefox/`, 138 under `m1-thunderbolt/`). Each needs to be confirmed
  as ours (then gets the copyright line) or re-marked as its source's.
- 273 of 437 files tagged GPL, ISC, BSD or MPL have no copyright or author line in their
  first 40 lines; ports need their upstream notices restored.
- Under `finch/` only 28 files carry Finch's copyright line and the files do not say which
  are Finch's and which are ours.
- Ten directories with GPL-derived code have no `NOTICE` (`m1-rust-kext`, `m1-gpu-rtkit`,
  `m1-dcp`, `m1-dcp-dart`, `m1-lkpi-extras`, `m1-cpufreq`, `m1-thermal`, `m1-drm72`,
  `m1-native-boot`, `m1-avd-capacity`); `m1-apcie-host/NOTICE` is the model.
- Licence texts still missing from `LICENSES/`: BSD-3-Clause, Swift-exception.
- Effort: three to five days, mostly mechanical, with a review per directory.

Further provenance notes from the licence pass of 19 November 2026. They do not
replace the counts above.

- `integrations/siliconforest/finch/`: SPDX tags found there are mostly `MIT`, with
  some `MIT OR Apache-2.0`. A search for the string "The Finch" in that directory
  found no copyright line. Finch copyright lines do appear in some patches under
  `cocoa/`, `terminal-app/`, `activity-monitor/`, and `libsystem-default/`. `NOTICE`
  says to treat `finch/` as Finch's until the files say which are Finch's and which
  are glue. Reconcile that with the "28 files" count above.
- `m1-native-input/` holds five copies of `IOHIDEventService.cpp` with the APSL-2.0
  header (already item F21 below) and no SPDX line on those copies.
- The vendored Chonkstep copy is GPL-3.0-only by its `LICENSE` and `Cargo.toml`.
  `dock/bindings/LICENSE` and `examples/LICENSE` are MIT, copyright iconidentify.
  The two `omarchy/plugins/*/LICENSE` files are the GPL-3 text. `NOTICE` had recorded
  those two plugin files as not read.
- `m1-apcie-bridge` has `NOTICE` files and almost no SPDX tags. Several early leaves
  (`m1-bringup`, `m1-keyboard`, `m1-network-*`, `m1-dart`, `m1-gpu-uat*`, and others)
  have no SPDX line. Some `PROVENANCE` notes still say original-code licence selection
  is pending. `core/`, `contracts/`, `probe/`, `userspace/`, `specs/`, and most of
  `tools/` and `tests/` likewise have no SPDX grant. `AGENTS.md` still says licence
  selection for original code is pending.
- `NOTICE` marks some entries "not verified" (Mesa, parts of drm-kmod and FreeBSD,
  Firefox as run here, neofetch, several fonts, components reached only through the
  build). Apple's binary driver licence is named there; which PureDarwin components
  it covers is not established.
- PureDarwin is mixed. `PUREDARWIN_LICENSE.txt` is BSD-2-Clause for that file.
  A PureDarwin maintainer (issue 23, comment linked in item 4) names pure MPL-2.0,
  MPL-2.0 OR MIT, and tri-licensed files. The tri-licence expressions were not named
  and are not assigned here. `docs/roadmap/issues/SF-0-index.md` and issue 23 still
  summarise PureDarwin's own files as BSD-2-Clause. Per-file terms are the headers
  in upstream PureDarwin.

### 7. Home paths and bench addresses (F16, F17, F19). Owner decides the scope; then work.
Counted on `release-prep`, outside frozen records (`reports/`, `archive/`, `planning/`,
`attempts/`, `revisions/`, `validation*/`, `AGENTS.md`, the vendored Chonkstep copy):

| Pattern | `tools/` | `docs/` | `integrations/` | `tests/` |
|---|---|---|---|---|
| Linux home path of the build machine | 0 files | 8 files, 11 places | 73 files, 346 places | 0 |
| macOS home path of the controller | 5 files, 8 places | 5 files, 11 places | 15 files, 15 places | 1 file |
| private-network bench addresses (`10.1.1.x`) | 5 files, 21 places | 3 files, 11 places | 74 files, 119 places | 2 files, 3 places |

- What an outsider reads first (`README.md`, `CONTRIBUTING.md`, `SECURITY.md`,
  `docs/design/`, `docs/RELEASE_CHECKLIST.md`, `LICENSES/`) contains none of them.
- The addresses are private-network addresses and the user name is the public account
  name: an embarrassment, not an exposure. They are nevertheless what makes the tools
  unusable elsewhere.
- **Not changed on this branch, on purpose:** the bench tools (`tools/pcie_iterate.sh`,
  `tools/m1_return_linux.sh`, `tools/gpu_desktop_stop.sh` and the hash-recorded
  `tools/m1_kernel_cycle.py`, `tools/m1_recovery.py`). They drive the one machine, are in use
  by other work today, and could not be tested from here. Next step: read host, user and
  controller directory from the environment (`M5_HOST` already exists in two of them) or
  from an untracked `config/lab.local.json`, with no default address in git.
- In `integrations/`, most of the Linux home paths are `file:///home/…` sources in Nix
  recipes: they go away with the source lock (5), not by search and replace.
- `docs/M1_KERNEL_CYCLE.md`, `docs/M1_RECOVERY.md` and the other `docs/M1_*.md`,
  `docs/SPRINT_*.md` files are records of the first bring-up and are not rewritten.
- Also: Linux `boot_id` values in 43 report files; one install note gives the exact free
  block range of the owner's disk.
- Effort: one day for the live tools once the bench is free; the recipes come with 5.

### 8. Frozen evidence and the agent work log (F11, F30). Owner.
`reports/` (979 files), 126 `attempts/` files, 336 logs, `archive/`, `planning/`, the parked
`m1-apcie-bridge` models and `AGENTS.md` (98 KiB of working instructions and log, with bench
addresses) document how the system was brought up. No credential or device identifier was
found in them beyond 7.
- With this repository going public as it is, they are published (they are in history either
  way). The remaining choice is whether they stay on `main` or move to an archive branch.
- `AGENTS.md` is loaded by tools and was not touched. Suggested: move the full file to
  `docs/history/` and keep a short `AGENTS.md` (rules that still hold: truthfulness, boundaries,
  required checks, naming, licence rules) that points to `CONTRIBUTING.md`.

### 9. Continuous integration (F13). Done in the tree; one check left.
See "Done". Left: confirm the first run on GitHub is green (the runner is Ubuntu 24.04; the
local run was on Arch), and delete or let expire the old failed runs (2).

## Medium

| Item | Audit | Kind | Effort |
|---|---|---|---|
| Apple applications as a feature: the README says exactly what runs (two applications, the owner's copies, nothing in the repository). Confirm this presentation, and that the screenshots, which show those two applications' windows, are wanted | F23 | Owner | decision |
| Tools that fetch a kernelcache from Apple's CDN and extract tables (`m1-ave/tools/`): publish or not | F22 | Owner | decision |
| Five copies of Apple's `IOHIDEventService.cpp` (APSL header intact) under `m1-native-input/`: reduce to patches if possible | F21 | Work | half a day |
| Clean-room status of reimplemented private frameworks (`sysmon`, CoreUI pieces, `UTTypeTable.inc`) was not assessed | audit, "not checked" | Owner | review |
| The 219 images in the tree were not opened by the audit; the six in `docs/images/` were | audit | Work | an hour |
| Issue comments that only the owner should rewrite or remove | | Owner | an hour |
| Remaining old names behind escape sequences (issue #60) | | Work | small |

## Before the switch

1. GitHub Support request for the old pull requests (1), and an answer.
2. Merge `release-prep`; see the workflow green; delete the old Actions runs and the
   branches that are not wanted (2).
3. Re-run the scans on `main`: gitleaks; the value search for Wi-Fi and disk identifiers; the
   hash comparison against `private/`; greps for session links and personal email domains.
4. Enable private vulnerability reporting (`SECURITY.md` relies on it); set the description
   and topics; check that GitHub detects the licence (it may show "Other": the root
   `LICENSE` is a notice, and the MIT grant is `LICENSE-SILICONFOREST-MIT`).
5. The owner reads the repository signed out, as an outsider would after the switch, and
   changes visibility himself.
