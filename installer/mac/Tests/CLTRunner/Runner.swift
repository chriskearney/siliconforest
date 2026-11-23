// Runs the Swift Testing suite as a plain executable. Command Line Tools-only Macs build the
// `swift test` bundle but don't run it; this does (scripts/test.sh). On Xcode, `swift test` works.
// Afterwards it detaches and deletes every per-test disk image (templates are kept for reuse).
import Foundation
import Testing
import SFEngine

@main struct CLTTestRunner {
    static func main() async {
        let code: Int32 = await Testing.__swiftPMEntryPoint(passing: nil)
        if ProcessInfo.processInfo.environment["SF_KEEP"] != "1" {
            ImageFixtures.cleanUp(ImageGuard.defaultRoot.appendingPathComponent("runs", isDirectory: true))
        }
        exit(code)
    }
}
