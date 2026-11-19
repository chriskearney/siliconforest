// SPDX-License-Identifier: MIT
// Original narrow view adapter. No Apple PaperKit implementation is included.
import Foundation
import SFPaperBridge

public class PaperViewController: NSViewController {
    public func display(_ url: Foundation.URL, readOnly: Bool) {
        SFPaperDisplay(self, url._bridgeToObjectiveC(), readOnly)
    }

    // Original probe entry; it exercises the same value bridge and display path.
    @objc(sfDisplayURL:readOnly:)
    public func sfDisplayURL(_ url: NSURL, readOnly: Bool) {
        display(Foundation.URL._unconditionallyBridgeFromObjectiveC(url), readOnly: readOnly)
    }
}
