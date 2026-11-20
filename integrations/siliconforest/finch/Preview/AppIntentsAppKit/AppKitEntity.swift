// SPDX-License-Identifier: MIT OR Apache-2.0
// AppIntents' AppKit helpers: keep entity annotations on the view that owns them.

@_exported import AppIntents
import AppKit
import ObjectiveC

private var entityIdentifierKey: UInt8 = 0

private final class EntityIdentifierBox: NSObject {
    let value: EntityIdentifier

    init(_ value: EntityIdentifier) {
        self.value = value
    }
}

extension NSView {
    public var appEntityIdentifier: EntityIdentifier? {
        get { (objc_getAssociatedObject(self, &entityIdentifierKey) as? EntityIdentifierBox)?.value }
        set {
            let box = newValue.map(EntityIdentifierBox.init)
            objc_setAssociatedObject(self, &entityIdentifierKey, box, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}
