# Inert P13 packet preparation

`prepare.py` assembles a fresh private packet locally. It has no SSH, install,
launch or GUI operation. Its input must explicitly set `app_execution_allowed`
to false. The packet and manifest are preparation artifacts, not authorization
to launch Preview or evidence that its closure is ready.

Keep the owner app, exact provider inputs and generated spec in ignored private
storage. Never put Apple binaries, app resources or private manifests in Git.

```sh
python3 integrations/siliconforest/finch/Preview/P13/prepare.py \
  --spec /owned/private/plan.json \
  --scratch /owned/private \
  --output /owned/private/new-p13-packet
```

The output must be a nonexistent direct child of the declared scratch directory.
The proposed M1 path must be a new `p13-*` child of
`/private/var/db/sfpreview-app`. No remote path is created or inspected by this
helper. A separate future guarded operator must verify that root is absent.

The spec pins the original base packet manifest and every original app file.
It declares provider files or trees with exact hashes/literal link inventories,
private fixtures, the planned environment, guard obligations and outstanding
blockers. All source bytes are checked before writing, and copied bytes are
checked again. The original app is checked before and after preparation.

Inherited directory aliases are detached inside the fresh copy before adding a
provider. No write or removal follows an inherited symlink into QTP or another
provider source. Read-only Nix directory modes are made writable only on owned
copied directories that need replacing. Source directories stay untouched.
Provider entries cannot target the app bundle or packet metadata.

The resulting `P13-plan.json` retains every unresolved condition.
`SHA256SUMS.json` records regular files and exact symlink strings. The archive
uses Python PAX with normalized uid/gid/mtime and a deterministic gzip header.
It includes full long link targets. Use the separately reviewed
`../unpack-private-stage.py` into an empty root, never guest native tar or an
active prefix. That extractor also validates rooted hardlink chains and a
regular manifest; this helper does not replace its controls.

Focused host boundary checks:

```sh
python3 -m unittest discover \
  -s integrations/siliconforest/finch/Preview/P13 -p 'test_*.py' -v
```

They exercise reproducibility, inherited-alias isolation, wrong input digests,
path escapes, existing output rejection and execution-authority rejection.
The fixture bytes are transport fixtures, not an application or native proof.

## Current private audit and handoff

Private reports live in `runs/preview/app-private/p13/`:

- `live-audit.json`: guarded read-only M1 file/header/import/export traversal;
  126 reachable images and 2,484 direct import records. Source app, active P12,
  retained p0, QTP and compositor remain unchanged. No app or probe executed.
- `external-targets-and-kernel.json`: all 36 original external QTP targets exist;
  current kernel build, boot time and compositor identity recorded under guards.
- `projected-audit.json`: direct-import coverage of the exact proposed providers,
  with observations, static predictions and unknown namespace records separated.
- `plan.json`: complete private spec, provider/fixture hashes, source receipts,
  exact planned environment, original universal/slice digests, before/after guard
  obligations and unresolved conditions. `app_execution_allowed` remains false.
- `handoff.json`: exact archive, tool and receipt hashes and reproduction commands.

REA portable arm64e header evidence
`ev_dd046758b100255fc8c1f272c5165849caca31fce4a28f3b7ded18ce5cb08668`
corroborates the 83 main load commands. Its outside-root providers remain
undetermined. The separate live audit models declared DYLD paths; neither
analysis proves runtime lazy bindings, computed dlopen paths, selector behavior,
shared-cache/load-order choices, or UI support. No native disassembler was
available on this Linux host; the portable artifact session was closed.

The proposed newer PDFKit exports cover all 46 direct Preview imports;
QuickLook and QuickLookUI cover 3/3 and 5/5. Their existing native reader receipts
are recorded. The exact CorePDF-tested Onyx pair is preserved. A new combined
PDFKit/QuickLook runtime check is still required; independent passing artifacts
do not prove every new combination.

The retained open AppIntents artifact covers all 320 direct Preview imports,
but its standalone runtime is still blocked on the name/error Foundation work.
No name or NSError bridge is duplicated here. Current P12 still lacks that image.

The Swift UTI overlay covers 15/16 direct Preview imports. The missing getter is
`Foundation.URLResourceValues.contentType`, whose mangling substitutes the final
word. Current coherent Foundation also lacks URLResourceValues metadata and
`URL.resourceValues(forKeys:)`. This is a coordinated value/resource/overlay
port, not an independent one-symbol patch. No guessed value layout, fake type
metadata, fabricated file type or unsupported-success implementation was added.

The old QTP Swift os provider remains selected through its existing fallback.
The minimal private Foundation-build os helper would drop two currently-covered
Preview Logger bindings, so it is excluded. A coherent Foundation check against
the preserved os provider remains an explicit guard obligation.

Seven active P12 framework links remain truncated. Their complete original
strings are retained only in this new local packet. No active link was repaired.
Static future candidates include TipKit, SwiftUI, observation/string-processing
and several smaller frameworks; `projected-audit.json` records exact gaps and
limits. They are not observed post-AppIntents dyld stops or a claim that P13 can
reach UI. Already-tested leaf alternatives are listed without bulk staging them.

Future execution must have new coordinator authorization and a pinned tested
coherent Foundation/AppIntents set. Under gui.lock, recheck kernel/PAC guard,
owner idle60, transport hashes/readlinks, existing windows and compositor/inject
state. Bound only the new owned process, preserve its HOME and original windows,
then repeat full/slice/off-box byte checks and every protected/provider/fixture
hash. Any backing-byte change stops repeat launches and preserves the evidence.
No restart, shared install, input to owner windows or active-stage mutation is
part of this packet.
