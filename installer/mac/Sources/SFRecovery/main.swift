import AppKit

// SFRecovery: the recoveryOS app (DESIGN §7). PLACEHOLDER.
//
// AppKit only (no SwiftUI, Combine or CryptoKit; §7.3). When built it will gate fail-closed
// (/System/Installation/CDIS, euid 0, volume/group UUIDs match SFInstall/plan.json, `bputil -d`
// reports Paired and one true recoveryOS), ask for the macOS owner's password, run `bputil -nc` and
// `kmutil configure-boot` through a PTY, read both back, clean up the markers, set SiliconForest for
// the next start only, and restart. `sf-launcher` falls back to Terminal + sf-step2.sh on any failure.
//
// This placeholder does none of that. Outside recoveryOS it refuses; inside it would exit 75 ("shut
// down") so the launcher's fallback path is what runs.

let inRecovery = FileManager.default.fileExists(atPath: "/System/Installation/CDIS")
FileHandle.standardError.write(Data("SFRecovery is a placeholder in this build (recoveryOS: \(inRecovery ? "yes" : "no")). Nothing was changed.\n".utf8))
exit(inRecovery ? 75 : 1)
