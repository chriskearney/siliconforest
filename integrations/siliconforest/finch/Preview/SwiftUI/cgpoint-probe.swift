import CoreGraphics
@inline(never) func equal<T: Equatable>(_ lhs: T, _ rhs: T) -> Bool { lhs == rhs }
enum Location: Equatable { case point(CGPoint); case automatic }
@main struct Proof {
 static func main() {
   precondition(MemoryLayout<CGPoint>.size == 16 && MemoryLayout<CGPoint>.alignment == 8)
   precondition(equal(CGPoint(x: 31, y: -19), CGPoint(x: 31, y: -19)))
   precondition(!equal(CGPoint(x: 31, y: -19), CGPoint(x: 31, y: 7)))
   precondition(equal(CGPoint(x: 0.0, y: -0.0), CGPoint(x: -0.0, y: 0.0)))
   precondition(equal(CGPoint(x: Double.infinity, y: 7), CGPoint(x: Double.infinity, y: 7)))
   precondition(!equal(CGPoint(x: Double.nan, y: 7), CGPoint(x: Double.nan, y: 7)))
   precondition(equal(Location.point(CGPoint(x: 31, y: -19)), Location.point(CGPoint(x: 31, y: -19))))
   precondition(!equal(Location.point(CGPoint(x: 31, y: -19)), Location.automatic))
   print("CGPOINT PASS generic equality, enum synthesis, signed zero, NaN/infinity, ABI layout")
 }
}
