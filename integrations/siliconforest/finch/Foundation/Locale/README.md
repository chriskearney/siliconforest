# Locale language identifiers for SwiftUI

The private Foundation overlay uses the installed ICU locale APIs to
extract a language code, add likely subtags and emit a BCP 47 tag.
The Swift string method passes the requested locale to CoreFoundation's
Unicode title-case operation.

Include `Language.swift` and the Clang module in `include/` when building
the private Swift Foundation dylib and link the installed ICU common
library. The M1 probe checks Traditional Chinese and English language
tag expansion and the Turkish dotted I.
