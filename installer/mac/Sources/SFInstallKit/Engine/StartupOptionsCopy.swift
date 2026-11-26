// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors

import Foundation

/// The wording for starting SiliconForest from startup options, in one place so every screen, the manual steps,
/// SFRecovery and sf-step2.sh say the same thing (Chris, 26 November 2026): hold the power button until
/// "Loading startup options", choose SiliconForest, and NOT Options. Options opens macOS Recovery, which can't
/// finish the setup (the stub is only mounted there, and nothing reads the stub's Setup marker).
public enum StartupOptionsCopy {
    public static let hold = "Hold the power button until you see “Loading startup options”."
    public static let notOptions = "Options opens macOS Recovery, which can't finish the setup."
    public static func choose(_ name: String) -> String { "Choose \(name), not Options. \(notOptions)" }

    /// A normal power-on while the startup disk is the stub and Setup hasn't run: macOS starts instead. Expected.
    public static let normalStartIsMacOS = "Until Setup has run, a normal start opens macOS. That is expected."

    /// One sentence for the places that only have room for one.
    public static func fallback(_ name: String) -> String {
        "If you start your Mac normally it opens macOS. To finish the setup, shut down, wait for the screen to go dark, then hold the power button until you see “Loading startup options”, and choose \(name), not Options. \(notOptions)"
    }

    /// SFRecovery's named screen when it finds itself in macOS's own Recovery.
    public static let macOSRecoveryTitle = "This is macOS Recovery, not SiliconForest's."
    public static func macOSRecoveryLead(_ name: String) -> String {
        "SiliconForest Setup can only finish in SiliconForest's own recovery. Shut down, then hold the power button until you see “Loading startup options”, and choose \(name), not Options."
    }
    public static func macOSRecoverySteps(_ name: String) -> [String] {
        ["Shut Down this Mac.", "Wait for the screen to go dark, then hold the power button until you see “Loading startup options”.", "Choose \(name), not Options."]
    }
    public static let macOSRecoveryNote = "Nothing was changed."
}
