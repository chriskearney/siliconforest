/* Finch AppKitOverlay.swift: the three Swift entry points SwiftUI imports. */

public func NSApplicationMain(
    _ argc: Int32, _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
) -> Int32 {
    return sf_NSApplicationMain(argc, argv)
}

extension NSMenuItem {
    /// A menu section's header (+sectionHeaderWithTitle:, refined for Swift as Apple's is).
    public static func sectionHeader(title: String) -> NSMenuItem {
        return title.withCString { bytes in
            let bridged = NSString(utf8String: bytes) ?? NSString()
            return sectionHeader(withTitle: bridged)
        }
    }
}

extension CGRect {
    /// Fills this rect in the current graphics context.
    /// - precondition: There must be a set current NSGraphicsContext.
    public func fill(using operation: NSCompositingOperation) {
        precondition(NSGraphicsContext.current() != nil,
                     "There must be a set current NSGraphicsContext")
        NSRectFillUsingOperation(self, operation)
    }
}
