// Runs the Swift Testing suite as a plain executable. Command Line Tools-only Macs build the
// `swift test` bundle but don't run it; this does (scripts/test.sh, which also cleans up the
// per-test disk images afterwards). On Xcode, `swift test` works.
import Foundation
import Testing

@main struct CLTTestRunner {
    static func main() async {
        let code: Int32 = await Testing.__swiftPMEntryPoint(passing: nil)
        exit(code)
    }
}
