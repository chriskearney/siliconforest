# Deprecated NSString cstring initializer

`NSStringCString.m` is the `NSString (SFDeprecatedCStringCompat)` category
from the overnight Foundation overlay. `initWithCString:` and
`stringWithCString:` try UTF-8, then ISO Latin-1.

The rest of `ObjCConstants.m` (locale identifiers, attributed strings,
sets, dictionaries, and number bridging) is unrelated and is not included.
