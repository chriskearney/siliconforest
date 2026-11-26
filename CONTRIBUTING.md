# Contributing to SiliconForest

Thank you for looking. The project is early and runs on one machine, so the most useful
contributions right now are reviews, corrections (especially of credits and licences), fixes
to code you can test without the hardware, and reports from people who know the upstream
projects better than we do.

## What you can build and run today

The whole system cannot yet be built from a clone (see "Building" in the
[README](README.md) and [`docs/RELEASE_CHECKLIST.md`](docs/RELEASE_CHECKLIST.md)). What runs
anywhere with Python 3.10+ and a C compiler:

```sh
python3 tools/check.py --sanitize --cross   # host tests (one needs an artefact not in git)
python3 tools/check_mutations.py
python3 tools/lab.py validate
python3 tools/sf_rename.py check            # naming rules; must print "check: clean"
```

Many directories under `integrations/siliconforest/` have host-only tests of their own
(`test_*.py`, `cargo test`); run the ones next to what you change. None of them contacts
hardware.

Please do not send changes that you could only have tested on an M1 without saying how you
tested them. A build is compile evidence; "works" means it was observed on the machine.

## Rules for code

- **Names.** New names follow [`docs/design/siliconforest-naming.md`](docs/design/siliconforest-naming.md)
  (`sf_`, `SF…`, `org.siliconforest.`). The old name stays only where it means upstream PureDarwin.
- **Style.** Follow the file you are in. Ported drivers keep the structure and names of
  their Linux or BSD original so that upstream changes can be followed.
- **No success stubs.** Missing functionality fails or is absent; it does not return success.
- **Frozen records.** Files under `reports/`, `archive/`, `planning/`, and directories named
  `revisions/`, `attempts/`, `validation*/` are records of what was done. They are not edited.
- **Safety-gated files** (`m1-storage/kernel/sf_nvme_wgate.c/.h`, the fence constants in
  `m1-storage/kernel-rw/sf_nvme_wring.h`, `m1-native-boot/reboot/sf_halt_gate.h`) decide
  where the disk driver may write and when the machine may halt. Changes to them need the
  maintainer's explicit agreement first; open an issue.

## Licence rules

1. **New original code is offered as MIT.** By contributing new code that you wrote,
   and that is not derived from another project, you agree it is licensed under the
   MIT License. The text, with the project's copyright notice, is
   [`LICENSE-SILICONFOREST-MIT`](LICENSE-SILICONFOREST-MIT). Put
   `SPDX-License-Identifier: MIT` and a copyright line in new files. The tree as it
   stands is not under that licence as a whole: [`LICENSE`](LICENSE) is a notice.
   Some existing files still need provenance review
   ([`docs/RELEASE_CHECKLIST.md`](docs/RELEASE_CHECKLIST.md)). This rule does not
   relicense existing files.
2. **Ported and adopted code keeps its licence.** If your change is derived from another
   project (a Linux driver, a BSD driver, Mesa, Finch, upstream PureDarwin, an Apple open-source
   release), the file carries that project's SPDX identifier and its original copyright
   notices, unchanged, and says where it came from (project, path, revision). A file ported
   from GPL-2.0 code is GPL-2.0. Add or update the `NOTICE` of the directory and, for a new
   source, the top-level [`NOTICE`](NOTICE). If the licence text is not yet in
   [`LICENSES/`](LICENSES/), add an unmodified copy and say where it came from.
3. **Never remove or alter** a copyright or licence line that is not yours.
4. **Mind the combinations.** Code shared between a GPL-2.0-only kernel extension and the
   GPL-3.0-only desktop must be under a licence both accept (MIT, BSD, ISC). When a Linux
   file is dual-licensed, keep the dual identifier.
5. **No Apple-proprietary material, ever.** No Apple binaries, frameworks, fonts, sounds,
   icons, firmware, SDK headers, kernelcache contents, or anything extracted, disassembled
   or transcribed from them; no leaked source. Reimplementations are written from public
   documentation, open-source releases and observed behaviour. The same holds for any other
   vendor's proprietary material.
6. **No private data.** No credentials, Wi-Fi details, serial numbers, MAC addresses, disk
   identifiers, firmware files or device logs in commits, issues or pull requests.

## Sign-off

Commits carry a `Signed-off-by:` line (`git commit -s`), by which you certify the
[Developer Certificate of Origin 1.1](https://developercertificate.org): that you wrote the
change or have the right to submit it under the licence of the file. There is no
contributor licence agreement.

## Changes that belong upstream

SiliconForest is a fork of PureDarwin and ports from Asahi Linux, Mesa and others. If a fix applies
to the upstream project as it is, please send it there too (or say so in the pull request and
we will); we would rather carry fewer patches than more.

## Issues and pull requests

- One topic per pull request, with what you ran and what you saw.
- Hardware reports: the model, what you did, the console or log lines. Remove serial
  numbers and addresses first.
- Credit or licence mistakes are treated as bugs with priority.
