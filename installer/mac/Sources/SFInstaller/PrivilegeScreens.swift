// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//
// Preview10: the Privileges screen (before any download or disk work) and the error box every live
// screen uses: what went wrong, the underlying error, where the logs are, and Show Log.

import SwiftUI
import AppKit
import SFInstallKit
import SFCopy
import SFDesign
import SFFlow
import SFHelperKit
import SFLiveDisk
import SFAppEngine

enum LogLinks {
    /// Opens a log in Console (the default app for .log); if it doesn't exist yet, reveals its folder.
    static func show(_ path: String) {
        let u = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path) { NSWorkspace.shared.open(u) }
        else { NSWorkspace.shared.activateFileViewerSelecting([u.deletingLastPathComponent()]) }
    }
}

/// An error, its underlying cause, and the logs (with Show Log).
struct LiveErrorBox: View {
    var message: String
    var note: String? = "Nothing on your disk was changed."
    @ObservedObject var live: LiveRun
    @Environment(\.theme) private var theme
    var body: some View {
        Panel(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Label(message, systemImage: "xmark.octagon.fill")
                    .font(SFType.bodyStrong).foregroundStyle(theme.critical).fixedSize(horizontal: false, vertical: true)
                if let note { Text(note).font(SFType.label).foregroundStyle(theme.textSecondary) }
                logLines
                buttons
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var logLines: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Log: \(live.appLogPath)").font(SFType.log).foregroundStyle(theme.textSecondary).textSelection(.enabled)
            Text("Helper log: \(live.helperLogPath)").font(SFType.log).foregroundStyle(theme.textSecondary).textSelection(.enabled)
        }
    }
    private var buttons: some View {
        HStack(spacing: 10) {
            Button("Show Log") { LogLinks.show(live.appLogPath) }.buttonStyle(SFTextButtonStyle()).fixedSize()
            Button("Show Helper Log") { LogLinks.show(live.helperLogPath) }.buttonStyle(SFQuietButtonStyle()).fixedSize()
        }
    }
}

struct LivePrivilegesScreen: View {
    @ObservedObject var s: Session
    @ObservedObject var live: LiveRun
    @Environment(\.theme) private var theme
    var body: some View {
        SnapScroll {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHead(title: Copy.Privileges.title, lead: Copy.Privileges.lead)
                Panel {
                    VStack(alignment: .leading, spacing: 10) {
                        helperRow
                        diskRow
                    }
                }
                detail
            }
        }
    }

    private var helperState: RowState {
        switch live.privileges {
        case .checking, .needsHelperApproval, .restartingHelper: return .working
        case .failed: return .fail
        case .needsFullDiskAccess, .ready: return .pass
        }
    }
    private var diskState: RowState {
        switch live.privileges {
        case .needsFullDiskAccess: return .working
        case .ready: return .pass
        default: return .waiting
        }
    }

    /// The helper row is a button except when the check already passed or is still starting.
    private var helperRowIsTappable: Bool {
        switch live.privileges {
        case .ready, .checking: return false
        default: return true
        }
    }
    private var diskRowIsTappable: Bool {
        switch live.privileges {
        case .needsFullDiskAccess: return true
        case .failed: return live.privileges.failedMentionsFullDiskAccess
        default: return false
        }
    }

    @ViewBuilder private var helperRow: some View {
        if helperRowIsTappable {
            TappablePhaseRow(Copy.Privileges.helperRow, state: helperState) { live.openLoginItems() }
        } else {
            PhaseRow(Copy.Privileges.helperRow, state: helperState)
        }
    }
    @ViewBuilder private var diskRow: some View {
        if diskRowIsTappable {
            TappablePhaseRow(Copy.Privileges.diskRow, state: diskState) { live.openFullDiskAccess() }
        } else {
            PhaseRow(Copy.Privileges.diskRow, state: diskState)
        }
    }

    @ViewBuilder private var detail: some View {
        switch live.privileges {
        case .checking:
            HStack(spacing: 10) { Spinner(size: 16, color: theme.accent); Text(Copy.Privileges.checking).font(SFType.body).foregroundStyle(theme.text) }
        case .restartingHelper:
            HStack(spacing: 10) { Spinner(size: 16, color: theme.accent); Text(Copy.Privileges.restarting).font(SFType.body).foregroundStyle(theme.text) }
        case .needsHelperApproval:
            LoginItemsHelp()
        case .needsFullDiskAccess(let r):
            FullDiskAccessHelp(report: r, helperPath: PrivilegeGate.helperPath(appBundle: live.appBundle))
        case .ready:
            Label(Copy.Privileges.continuing, systemImage: "checkmark.circle.fill").font(SFType.bodyStrong).foregroundStyle(theme.text)
        case .failed(let m):
            LiveErrorBox(message: m, live: live)
            LoginItemsHelp()
        }
    }
}

/// A PhaseRow that is a button: pointer cursor and a chevron, so it reads as clickable.
struct TappablePhaseRow: View {
    var title: String
    var state: RowState
    var action: () -> Void
    @Environment(\.theme) private var theme
    init(_ title: String, state: RowState, action: @escaping () -> Void) {
        self.title = title; self.state = state; self.action = action
    }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                PhaseRow(title, state: state)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
    }
}

struct WaitingLine: View {
    var text: String
    @Environment(\.theme) private var theme
    var body: some View {
        HStack(spacing: 10) {
            Spinner(size: 14, color: theme.accent)
            Text(text).font(SFType.label).foregroundStyle(theme.textSecondary)
        }
    }
}

struct LoginItemsHelp: View {
    @Environment(\.theme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Copy.Privileges.waiting).font(SFType.bodyStrong).foregroundStyle(theme.text)
            Text(Copy.Privileges.waitingBody)
                .font(SFType.body).foregroundStyle(theme.text).fixedSize(horizontal: false, vertical: true)
            WaitingLine(text: Copy.Privileges.waitingLine)
        }
    }
}

struct FullDiskAccessHelp: View {
    var report: PrivilegeReport
    var helperPath: String
    @Environment(\.theme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Turn on Full Disk Access for SFHelper").font(SFType.bodyStrong).foregroundStyle(theme.text)
            Text("Even administrators need Full Disk Access to read or write the internal disk directly. The helper uses it to read the partition table, which identifies the disk, and to write the new partitions. It doesn't read your files.")
                .font(SFType.body).foregroundStyle(theme.text).fixedSize(horizontal: false, vertical: true)
            steps
            WaitingLine(text: "Checking every few seconds. The installer continues when access is on.")
            Text("macOS answered: \(report.detail ?? "access denied") (\(report.probe))").font(SFType.caption).foregroundStyle(theme.textTertiary)
        }
    }
    private var steps: some View {
        VStack(alignment: .leading, spacing: 6) {
            step(1, "Click Open Full Disk Access Settings.")
            step(2, "Turn on SFHelper in the list. macOS may ask for your password.")
            step(3, "Not in the list? Click +, press ⌘⇧G, paste the path below, click Open, then turn SFHelper on.")
            Text(helperPath).font(SFType.log).foregroundStyle(theme.text).textSelection(.enabled)
                .padding(.vertical, 6).padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: 8).fill(theme.text.opacity(0.06)))
                .padding(.leading, 26)
        }
    }
    private func step(_ n: Int, _ t: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n).").font(SFType.labelStrong).foregroundStyle(theme.accent).frame(width: 16, alignment: .trailing)
            Text(t).font(SFType.body).foregroundStyle(theme.text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
