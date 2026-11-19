# ModelIO load identity only

Preview has a strong ModelIO load command but no direct API imports. A static
audit of its 118 currently resolvable images found no other ModelIO consumer
and no required ModelIO symbols. This does not cover dynamic lookups or future
providers that are currently absent.

`modelio-load.nix` supplies that library identity, version 268.2.2/compatibility
1, with **zero implemented ModelIO APIs**. It exports two original scope
markers, no Apple function or Objective-C class, and has no constructors or
asset operations. A future typed import still fails binding until a real
implementation supplies it. This must never be reported as ModelIO support.

The standalone arm64 M1 probe passed dlopen and the explicit zero-API scope
check; both hashes were unchanged. The next bounded original Preview launch
loaded the carrier and stopped at missing AnnotationKit. All 174 app files
remained identical to the owner source. No Preview UI was reached.

The carrier is private and process-scoped. It changes neither the unmodified
application's load commands nor shared installed frameworks.
