import Foundation

/// The recovery bundle's script parts (DESIGN §7.1): `sf-launcher` and the Terminal fallback
/// `sf-step2.sh`. Shipped in the app at `Contents/Resources/RecoveryPayload/`; read from
/// `installer/mac/Recovery/` in the source tree.
public enum RecoveryPayload {
    public static var directory: URL {
        if let res = Bundle.main.resourceURL?.appendingPathComponent("RecoveryPayload"),
           FileManager.default.fileExists(atPath: res.appendingPathComponent("sf-launcher").path) { return res }
        return URL(fileURLWithPath: #filePath)   // …/installer/mac/Sources/SFEngine/Engine/RecoveryPayload.swift
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Recovery", isDirectory: true)
    }

    /// (path inside `Contents/`, bytes, executable)
    public static func files() -> [(String, Data, Bool)] {
        let d = directory
        func read(_ n: String) -> Data { (try? Data(contentsOf: d.appendingPathComponent(n))) ?? Data("#!/bin/sh\necho missing \(n)\nexit 1\n".utf8) }
        let info = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict>
            <key>CFBundleExecutable</key><string>sf-launcher</string>
            <key>CFBundleIdentifier</key><string>org.siliconforest.setup</string>
            <key>CFBundleName</key><string>SiliconForest Setup</string>
            <key>CFBundlePackageType</key><string>APPL</string>
            <key>LSMinimumSystemVersion</key><string>13.5</string>
            </dict></plist>

            """
        return [("Info.plist", Data(info.utf8), false),
                ("MacOS/sf-launcher", read("sf-launcher"), true),
                ("Resources/sf-step2.sh", read("sf-step2.sh"), true)]
    }
}
