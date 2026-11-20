/* SPDX-License-Identifier: MIT */
extension CGRect: Equatable {
    public static func == (lhs: CGRect, rhs: CGRect) -> Bool { CGRectEqualToRect(lhs, rhs) }
}

extension CGRect: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(origin.x)
        hasher.combine(origin.y)
        hasher.combine(size.width)
        hasher.combine(size.height)
    }
}

extension CGRect: @unchecked Sendable {}

extension CGRect {
    public static var zero: CGRect { CGRectMake(0, 0, 0, 0) }
    public var isEmpty: Bool { CGRectIsNull(self) || size.width == 0 || size.height == 0 }
    public func intersection(_ other: CGRect) -> CGRect { CGRectIntersection(self, other) }
    public func union(_ other: CGRect) -> CGRect { CGRectUnion(self, other) }
}
