# Swift Observation for Preview

`build.nix` compiles the Swift 6.3.3 Observation runtime from the same
`swiftlang/swift` release and fixed-output source pin used by the retained
Swift core. It emits the arm64 dylib and public/private module interfaces.
The source remains under Apache 2.0 with the Swift runtime library exception,
with the full upstream license in the package.

The cross SDK exposes `os/lock.h` through a private Clang module for the
upstream locking code. The Swift thread-local entry points use a private POSIX
pthread key. The SwiftUI SPI collects and merges access lists in the Observation
module so this SwiftUI port can use the same TLS and the upstream list layout
without referring to a reserved pthread slot or rebinding storage.

Build with:

```sh
nix-build --extra-experimental-features 'nix-command flakes' --no-out-link \
  integrations/siliconforest/finch/Preview/Observation/build.nix
```

The separate arm64 probe exercises key-path filtering, nested scopes, one-shot
notifications, merged SwiftUI access lists, and cancellation on the M1. The
dylib supplies all eight Observation symbols imported by Preview. Compiling a
client that uses `@Observable` also requires a compatible host macro plugin.
