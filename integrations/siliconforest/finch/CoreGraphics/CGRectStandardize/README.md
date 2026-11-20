# CGRectStandardize

AppIntents binds these five symbols to
`/System/Library/Frameworks/CoreGraphics.framework/Versions/A/CoreGraphics`:

- `_CGRectEqualToRect`
- `_CGRectIntersection`
- `_CGRectIsEmpty`
- `_CGRectStandardize`
- `_CGRectUnion`

The loaded image is the additions wrapper
`657c570788d1f1c936a266b30597ad3c59e6dc11f85e503125c7726e939ad6c0`.
Its install name is `CoreGraphics.sf-additions`. It reexports
`@loader_path/CoreGraphics.sf-under`. That under image is
`d7f137d1a64de511b669f3dcf88194fb12d3a32ff6ccd27d24676e4d7167077b`,
600 exports. It already defines the four rectangle calls above.
`_CGRectStandardize` is the only missing name in this set. `CGRectDivide`
is also absent and is not one of these imports. The Swift overlay in
`Geometry.swift` forwards intersection, union, and equality. It does not
define the C symbol.

`CGRectStandardize.c` keeps null and infinite classification on the
provider exports `CGRectIsNull`, `CGRectIsInfinite`, and `CGRectNull`.
The negative-extent rule is the retained Finch `CGGeometry.c` rule: add a
negative width or height to that origin, then store the positive size. A
zero side is empty and is not rewritten for that reason. A null rectangle
becomes the provider `CGRectNull`. An infinite rectangle is returned
unchanged.

On this provider, `CGRectNull` is origin `+inf,+inf` and size `0,0`
(`null=1`, `empty=1`, `infinite=0`). `CGRectInfinite` is origin
`-8.9884656743115795e+307` and size `+inf,+inf` (`null=0`, `empty=0`,
`infinite=1`). An origin at either signed infinity is null, so standardize
returns the canonical null rectangle. A NaN side is not negative: that
side stays NaN, and a negative other side is still standardized.

Build a private framework directory. Copy the additions wrapper unchanged.
Copy the under image, give that copy the install name
`@loader_path/CoreGraphics.sf-base`, and rehash its ad-hoc signature.
Compile `CGRectStandardize.c` into a new
`CoreGraphics.sf-under` that reexports the base and keeps the under install
name `/System/Library/Frameworks/CoreGraphics.framework/Versions/A/CoreGraphics`.
The new image's own export trie contains `_CGRectStandardize`. The 600 base
names stay available through the reexport. The wrapper's 15 own names stay
in the unchanged wrapper. Do not write the active framework.

The client is `probe.c`. It dlopens the private wrapper and the base.
`dlsym` takes the C spelling without the Mach-O underscore. The base must
not export `CGRectStandardize`. Numeric cases are fixed: `(10,20,-5,-8)`
becomes `(5,12,5,8)`, a positive rectangle stays, a zero side stays, and
`(9,3,-4,0)` becomes `(5,3,4,0)`. Null, infinite, and NaN cases use the
base predicates as the reference. Intersection, union, emptiness, and
equality on those rectangles must match the base image.

The tested under image is
`5736fda613cc8bfe627c8100b1a51b791a8bc0407168784d1881042fb0e93d97`.
The tested probe is
`e254178f016a21f1a37a99021d3bdb1c68fe0cf1d3323f47a1804921cbb6fd82`.
Headless receipt
`runs/preview/cg-geometry-wt/runs/cg-geometry/evidence/cg-geometry-20261119T120301Z.json`
exited 0. An earlier receipt, `cg-geometry-20261119T120232Z.json`, used the
same under image and failed only where the probe compared NaN with `==`.
Uploaded bytes, the active wrapper, the active under, the system
CoreGraphics image, and QTP Foundation
`94a07b510d116a7cfb4f302708f1a3ee7286d4be9c94037b77db13dc48959c2f`
stayed unchanged. Compositor PID 125 stayed unchanged. No AppIntents or
Preview launch.

The linker warns that an `@loader_path` dependent is ineligible for the
dyld shared cache. This M1 dyld loaded the private chain. This slice does
not replace the active CoreGraphics files. Machine-specific link and runner
scripts stay in the ignored `runs/` scratch.

Prepare a fresh directory and check the recorded digests:

```sh
python3 integrations/siliconforest/finch/CoreGraphics/CGRectStandardize/prepare.py \
  --output /path/to/fresh/owned/cgrect-standardize-sources
```
