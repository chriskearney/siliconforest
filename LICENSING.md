# Licensing of this repository

Read [`LICENSE`](LICENSE) first.

SiliconForest contains code under several licenses. Original SiliconForest
code is MIT-licensed. Third-party code retains its existing terms. Some
files still need provenance review.

[`LICENSE`](LICENSE) is a notice. It is not a grant, and it does not license
the repository as a whole under MIT. The MIT grant for original SiliconForest
code, with the copyright notice "Copyright (c) 2026 Chris Kearney and the
SiliconForest contributors", is
[`LICENSE-SILICONFOREST-MIT`](LICENSE-SILICONFOREST-MIT). It covers files
written for this project that were not ported, adopted, or copied.
[`LICENSES/MIT.txt`](LICENSES/MIT.txt) is a generic template with placeholders.
It is not that grant.

Everything else keeps the licence of the code it derives from. This file
does not relicense it.

- Full texts are in [`LICENSES/`](LICENSES/). [`LICENSES/README.md`](LICENSES/README.md)
  says where each copy came from.
- [`NOTICE`](NOTICE) names projects, the licence each source declares, and what
  was taken. Its header says it is a provenance record, not a legal review.
  Per-directory `NOTICE` files are more specific where they exist.
- The PureDarwin base is mixed. `PUREDARWIN_LICENSE.txt` is BSD-2-Clause for
  that licence file. A PureDarwin maintainer says the project also includes
  pure MPL-2.0, MPL-2.0 OR MIT, and tri-licensed files
  ([comment](https://github.com/chriskearney/siliconforest/issues/23#issuecomment-6984090313)).
  Apple's XNU and other Darwin code are APSL-2.0, or the licence named in the
  file. Per-file terms are the headers in
  [upstream PureDarwin](https://github.com/PureDarwin/PureDarwin).
- Crediting a source in the README or in `NOTICE` does not satisfy GPL-2.0,
  APSL-2.0, or any other licence. Those terms include the licence text,
  notices, source availability, and the APSL's modification notices. The
  credits list does not say which terms apply to which file, because the
  files are not separated by licence.

Provenance that is still open (SPDX tags without a copyright line, missing
`NOTICE` files, unverified headers) and the open questions about distributing
a combined kernel collection or system image are in
[`docs/RELEASE_CHECKLIST.md`](docs/RELEASE_CHECKLIST.md), items 4 and 6.
[`AGENTS.md`](AGENTS.md) still says licence selection for original code is
pending. Status: [`LICENSE_STATUS.md`](LICENSE_STATUS.md).

A kernel collection or a system image built from this repository combines
programs under different licences. Nothing here states that such a combination
may be distributed.
