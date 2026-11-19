# Swift regex runtime for Preview

This cross-build uses upstream Swift String Processing
`efe8986824694c53fd5e94a4c634f20b3682baeb` (Swift 6.3.3 release).
It builds the parser, matcher and Unicode tables without changes to the
upstream implementation. The package includes the upstream license.

Stage both `libswift_RegexParser.dylib` and
`libswift_StringProcessing.dylib` in the private Swift library directory.
The matcher exports all nine String Processing symbols imported by Preview.

The separate M1 probe tests case-folded matching, canonical Unicode
equivalence, match ranges, multiple matches, and rejection of invalid regex
syntax.
