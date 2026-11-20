# CoreTransferable for SwiftUI

The pinned Finch source implements data, file, proxy, and Codable
representations for the SwiftUI dependency. The private build uses the
prepared Preview Foundation and UniformTypeIdentifiers modules, the
packaged Combine framework, and the matching Swift 6.3.3 runtime.
`prepare.sh <Finch CoreTransferable.swift> <fresh directory>` verifies
the source digest and applies the compatibility patch before compilation
as the resilient module `CoreTransferable`. The framework installs at
`/System/Library/Frameworks/CoreTransferable.framework/Versions/A/CoreTransferable`.

The patch uses the existing URL APIs, the original JSON encoders and
decoders with their Combine protocols, and temporary directories created
with `mkdtemp`. Transfers reject invalid generated filenames and copy
without overwriting an existing destination. The staged subset omits the
`NSItemProvider` registration extensions. Keep Finch's MIT and Apache
license notices with builds.

The native test covers Codable file export and import, text decoding
including rejection of malformed UTF-8, and URL import.
