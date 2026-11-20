# Licence status

The root [`LICENSE`](LICENSE) is a notice. This repository is not licensed as a
whole under the MIT License.

SiliconForest contains code under several licenses. Original SiliconForest
code is MIT-licensed. Third-party code retains its existing terms. Some
files still need provenance review.

- The MIT grant for original SiliconForest code, with "Copyright (c) 2026
  Chris Kearney and the SiliconForest contributors", is
  [`LICENSE-SILICONFOREST-MIT`](LICENSE-SILICONFOREST-MIT). It covers files
  written for this project and not ported, adopted, or copied. It does not
  cover the rest of the repository.
  [`LICENSES/MIT.txt`](LICENSES/MIT.txt) is a template with placeholders, not
  that grant.
- Ported and adopted code keeps the licence of the code it derives from.
  [`NOTICE`](NOTICE) is the provenance record. [`LICENSES/`](LICENSES/) holds
  the texts that were copied in. The explanation is
  [`LICENSING.md`](LICENSING.md).
- [`AGENTS.md`](AGENTS.md) still says: "License selection for original code is
  pending; do not relicense upstream code."

What remains is [`docs/RELEASE_CHECKLIST.md`](docs/RELEASE_CHECKLIST.md):

- Item 4, and the notes under it: GPL-2.0 kernel extensions prelinked with
  the APSL kernel, and the related question of Apache-2.0 terms combined with
  GPL-2.0-only code. The checklist records the question. It does not answer
  on what terms a built collection or system image may be distributed.
- Item 6, and the notes under it: per-file headers, SPDX `MIT` tags with no
  copyright line, missing `NOTICE` files, and other provenance still to review.
- The PureDarwin base is mixed (BSD-2-Clause for `PUREDARWIN_LICENSE.txt`,
  MPL-2.0, MPL-2.0 OR MIT, tri-licensed files as a PureDarwin maintainer
  stated, MPL-2.0 OR BSD-2-Clause where `NOTICE` read that on a file, and
  APSL-2.0 for Apple's XNU and other Darwin code). Per-file terms are
  upstream PureDarwin's headers:
  <https://github.com/PureDarwin/PureDarwin>. The maintainer's comment:
  <https://github.com/chriskearney/siliconforest/issues/23#issuecomment-6984090313>.

Those checklist items remain open. The README of 7 to 9 November 2026, which
said that no project-wide distribution licence had been selected and pointed
at this file, is kept at
[`docs/history/README-2026-11-09.md`](docs/history/README-2026-11-09.md).

New original code offered by a contributor is MIT under
[`LICENSE-SILICONFOREST-MIT`](LICENSE-SILICONFOREST-MIT), as
[`CONTRIBUTING.md`](CONTRIBUTING.md) says. That rule does not relicense files
already in the tree.

Nothing here relicenses another project's code, chooses among dual-licence
options, or states that a combined kernel collection or system image is
distributable.
