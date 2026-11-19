# Swift uniform type identifier overlay

This private Swift overlay wraps SiliconForest's retained Objective-C UTType.
Identifier lookup, extension lookup, and type conformance use its actual type
registry. The Swift value compares and hashes its identifier.

Build with an explicit Foundation URL overlay input. Import the resulting
Swift module with `-I$out/usr/lib/swift -I$out/include`. A packaged M1 probe
loaded the private Swift overlay and verified PDF identifier resolution,
preferred extension, equality, and conformance. The system framework was
unchanged.
