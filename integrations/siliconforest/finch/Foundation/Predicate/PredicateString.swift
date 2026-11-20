// SPDX-License-Identifier: Apache-2.0 WITH Runtime Library Exception
// StringProtocol entry points used by PredicateExpressions string evaluation.
// The pinned FoundationInternationalization sources call these methods. This
// SDK's NSString declares caseInsensitiveCompare, localizedCompare, and
// rangeOfString:options:, and does not declare localizedStandardContainsString.
// localizedStandardContains uses the standard search mask: case, diacritic,
// and width insensitive.

extension StringProtocol {
    public func caseInsensitiveCompare<T: StringProtocol>(_ aString: T) -> ComparisonResult {
        String(self)._bridgeToObjectiveC().caseInsensitiveCompare(String(aString))
    }

    public func localizedCompare<T: StringProtocol>(_ string: T) -> ComparisonResult {
        String(self)._bridgeToObjectiveC().localizedCompare(String(string))
    }

    public func localizedStandardContains<T: StringProtocol>(_ string: T) -> Bool {
        // NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch | NSWidthInsensitiveSearch.
        // This header's CompareOptions lists the first flag only.
        let mask = String.CompareOptions(rawValue: 1 | 128 | 256)
        let found = String(self)._bridgeToObjectiveC().range(of: String(string), options: mask)
        return found.location != NSNotFound
    }
}
