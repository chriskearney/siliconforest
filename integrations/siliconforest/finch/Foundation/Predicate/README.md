# Foundation Predicate

Preview's Foundation image imports Predicate and PredicateExpressions. TipKit's
later `Tips.Rule` initializer needs these real Foundation types. This slice
does not emit TipKit symbols.

`sources.json` pins eight read-only swift-foundation files and this directory's
original files. `prepare.py` checks those digests, copies this slice, and
writes a patched `PredicateExpression.swift` into a new directory. It does not
modify the pin.

The pinned `PredicateError.==` compares an undefined variable with
`rhs == .undefinedVariable`. That static property is a `PredicateError`, so the
call is the same function. Two undefined-variable values recurse until the
stack guard. The other three cases already match `rhs._error`. The patch makes
the undefined-variable case match `rhs._error` the same way. Upstream
swift-foundation `main` still has the recursive line. The pin stays
`0be562e4693cfd0c146755304f3b2a7f4f46a2991da9b9a14cda0ed40530a69b`. The patched
file is `0233f2fe3a541f76fb3251aca920081fbad25dd575ecd082111868dcdbefb7af`.

```sh
python3 integrations/siliconforest/finch/Foundation/Predicate/prepare.py \
  --expression /path/to/pinned/PredicateExpression.swift \
  --output /path/to/fresh/predicate-sources
```

Compile the patched expression with the other seven pinned files,
`PredicateString.swift`, and `PredicateDebugString.swift`, on the read-only P13
Foundation `2de8e8fc00a7acd6b1633add2db6cf13c9a7f6892d0c34250665bdd69921f0d6`
and its frozen url-resource-values recipe. Keep `-D FOUNDATION_FRAMEWORK`,
whole-module optimization, and library evolution. `Synchronization.swiftmodule`
is absent, so `VariableID` uses `LockedState`. `PredicateDebugString.swift` is
the package description protocol the pinned localized-string file extends.
Evaluation does not read that state. `PredicateString.swift` implements
`caseInsensitiveCompare`, `localizedCompare`, and `localizedStandardContains`.
This SDK's `NSString` has no `localizedStandardContainsString:`. The standard
search calls `range(of:options:)` with mask `1 | 128 | 256`. The header names
only the case-insensitive bit.

The tested library is
`aa7de512b8f76a22d9f9484455b5fccd35af9b99f5d0e9c943b54bfaefd530c0`.
It replaces `10eba5cdcf47c5aa23320b9f103240808f44c1c6d43b46d07da7407c118e12cd`,
whose `==` still recursed. Against baseline `2de8e8fc…` the export trie is
5362, then 5627, lost 0, gained 265. Metadata and witnesses are compiler
output. The usableFromInline `build_KeyPath` Preview imports is present. The
public `build_KeyPath` is `@_alwaysEmitIntoClient` and calls it.

Headless receipt
`runs/preview/predicate-wt/runs/predicate/evidence/predicate-20261119T162302Z.json`
is PID 6256, exit 0, no signal. The client evaluated value, both `build_Arg`
overloads, `Equal`, every `ComparisonOperator`, `PredicateError` equality,
a thrown undefined variable and its debug description, an unbound variable,
a wrong variable, case-insensitive and localized string order, ASCII
`localizedStandardContains`, and `KeyPath` comparison and equality on a
`Codable` row. `Caf\u{00E9}` (`43,61,66,e9`) contained `cafe` and `f\u{00E9}`,
and case-insensitive compare with `caf\u{00E9}` returned 0. That diacritic
result is one observed pair. Width was not isolated. Uploaded bytes, QTP
Foundation `94a07b510d116a7cfb4f302708f1a3ee7286d4be9c94037b77db13dc48959c2f`,
`/usr/lib/swift/libswiftFoundation.dylib`
`f13a6aa6f296ff4ec2a06eb466d9bb12ee1473b30c42070decd0d7022048524d`, and
compositor PID 125 stayed unchanged. Owner guard `active=0`. No Preview,
TipKit, or AppIntents launch. The dylib is not installed.

TipKit keeps `EventPredicateExpression`, the four conformances, and the generic
`Tips.Rule` initializer. `NotEqual`, regex, arithmetic, sequence, and
`NSPredicate` conversion are outside this slice. Key-path encode and decode
throw because `ReflectionInternal` is absent. `==` still ignores the `String?`
payload on the failure cases, matching the pin. The synthesized hash includes
that payload. The Error.localizedDescription fallback trap is unchanged.
Machine-specific emit, link, and runner scripts stay in ignored `runs/predicate/`.
