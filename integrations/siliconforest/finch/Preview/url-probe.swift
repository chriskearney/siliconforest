// SPDX-License-Identifier: MIT
// Synthetic value/bridge/lifetime checks only. No file is opened or written.
import Foundation

@main
struct URLProbe {
    static func main() {
        let path = "/tmp/preview URL fixture"
        let reference = NSURL(fileURLWithPath: path)
        let value = URL._unconditionallyBridgeFromObjectiveC(reference)
        precondition(value.isFileURL && value.path == path)
        precondition(value._bridgeToObjectiveC() === reference)
        precondition(URL(string: "") == nil)
        precondition(!value.startAccessingSecurityScopedResource())
        value.stopAccessingSecurityScopedResource()
        var values: Set<URL> = []
        for _ in 0..<10000 {
            let copy = value
            values.insert(copy)
            precondition(copy.path == path && copy._bridgeToObjectiveC() === reference)
        }
        precondition(values.count == 1)
        let dictionary = ["meaning": 42]
        let bridged = dictionary as NSDictionary
        let restored = bridged as! [String: Int]
        precondition(restored == dictionary)
        let text: NSString = "legacy string"
        precondition((text as String) == "legacy string")
        let date = Date(timeIntervalSinceReferenceDate: 123)
        precondition((date as NSDate).timeIntervalSinceReferenceDate() == 123)
        print("URL bridge=PASS copies=10000 hash=PASS legacy-string-dictionary-date=PASS scope-acquired=false")
    }
}
