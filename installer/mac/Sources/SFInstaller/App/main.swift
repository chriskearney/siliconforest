import SwiftUI
import AppKit
import SFInstallKit
import SFCopy
import SFDesign
import SFFlow

// SiliconForest Installer
//
//   SFInstaller                       native full screen, dry run on the simulated J293 disk
//   SFInstaller --windowed            stay in a window (tests, development)
//   SFInstaller --real                read-only analysis of this Mac (never writes)
//   SFInstaller --fixture NAME        another simulated disk (see Fixtures/disks)
//   SFInstaller --speed X             dry-run pace (1 = default)
//   SFInstaller --fail-step STEP      inject a failure to see rollback
//   SFInstaller --appearance light|dark
//   SFInstaller --snapshot DIR [--sizes 1280x800@2,1512x982@1]   render every screen offscreen
//   SFInstaller --render-icon DIR     write the .iconset PNGs used by make-app.sh

struct LaunchOptions {
    var args: [String: String] = [:]
    init() {
        let a = Array(CommandLine.arguments.dropFirst())
        var i = 0
        while i < a.count {
            if a[i].hasPrefix("--") {
                let k = String(a[i].dropFirst(2))
                if i + 1 < a.count, !a[i + 1].hasPrefix("--") { args[k] = a[i + 1]; i += 2 } else { args[k] = "true"; i += 1 }
            } else { i += 1 }
        }
    }
    subscript(_ k: String) -> String? { args[k] }
    var has: (String) -> Bool { { args[$0] != nil } }
}

@MainActor
func makeSession(_ o: LaunchOptions) -> Session {
    if o.has("real") {
        return Session(mode: .readOnly, backend: RealDiskBackend())
    }
    let name = o["fixture"] ?? "j293-512"
    let fixture = (try? DiskFixture.named(name)) ?? (try! DiskFixture.named("j293-512"))
    var failures: [FailureInjection] = []
    if let st = o["fail-step"], let step = StepID(rawValue: st) { failures.append(FailureInjection(step: step, atFraction: 0.45)) }
    let speed = Double(o["speed"] ?? "1") ?? 1
    let s = Session(mode: .dryRun, backend: SimulatedDiskBackend(fixture: fixture, timeScale: speed, failures: failures))
    s.stepPace = speed
    return s
}

/// Supplies theme and screen size from the live environment.
struct AppRoot: View {
    @ObservedObject var session: Session
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            RootView(s: session)
                .environment(\.theme, Theme(isDark: scheme == .dark))
                .environment(\.screenSize, geo.size)
        }
        .ignoresSafeArea()
        .task { await session.load() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let options: LaunchOptions
    var session: Session!
    var window: NSWindow!
    var keyMonitor: Any?

    init(options: LaunchOptions) { self.options = options }

    func applicationDidFinishLaunching(_ notification: Notification) {
        SFType.registerFonts()
        session = makeSession(options)
        NSApp.applicationIconImage = renderIcon(side: 512)
        buildMenu()
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let size = NSSize(width: min(1440, screen.visibleFrame.width), height: min(900, screen.visibleFrame.height))
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = false
        window.minSize = NSSize(width: 1024, height: 700)   // VISUAL §8
        window.collectionBehavior = [.fullScreenPrimary]
        window.contentView = NSHostingView(rootView: AppRoot(session: session))
        window.title = Copy.installer
        window.backgroundColor = .black
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Native full screen in its own Space (D9); menu bar, Dock reveal, Mission Control and
        // force quit all keep working. `--windowed` stays in a window (tests, development).
        if !options.has("windowed") { window.toggleFullScreen(nil) }
        // Esc leaves full screen (VISUAL §8); outside full screen it asks to quit.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, e.keyCode == 53 else { return e }
            if self.session.showQuitConfirm || self.session.showDetails || self.session.showCommands || self.session.showWhatIs {
                self.session.showQuitConfirm = false; self.session.showDetails = false; self.session.showCommands = false; self.session.showWhatIs = false
                return nil
            }
            if self.window.styleMask.contains(.fullScreen) { self.window.toggleFullScreen(nil) } else { self.session.requestQuit() }
            return nil
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if session.quitConfirmed { return .terminateNow }
        session.requestQuit()
        return .terminateCancel
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        session.requestQuit()
        return false
    }

    private func buildMenu() {
        let main = NSMenu()
        func menu(_ title: String, _ items: [NSMenuItem]) {
            let item = NSMenuItem(); let m = NSMenu(title: title)
            items.forEach(m.addItem); item.submenu = m; main.addItem(item)
        }
        menu("Installer", [NSMenuItem(title: "Quit \(Copy.installer)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")])
        menu("Edit", [NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"),
                      NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"),
                      NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"),
                      NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")])
        let details = NSMenuItem(title: "Show Details", action: #selector(toggleDetails), keyEquivalent: "l"); details.target = self
        menu("View", [details, NSMenuItem(title: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")])
        menu("Window", [NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")])
        let logs = NSMenuItem(title: "Open Log Folder", action: #selector(openLogs), keyEquivalent: ""); logs.target = self
        let diag = NSMenuItem(title: "Export Diagnostics…", action: #selector(exportDiagnostics), keyEquivalent: ""); diag.target = self
        menu("Help", [logs, diag])
        NSApp.mainMenu = main
    }

    @objc func toggleDetails() { withAnimation(SFMotion.screen) { session.showDetails.toggle() } }
    @objc func openLogs() { NSWorkspace.shared.open(Journal.defaultDirectory()) }
    @objc func exportDiagnostics() { session.showDiagnostics = true }
}

@MainActor
func renderIcon(side: CGFloat) -> NSImage? {
    let r = ImageRenderer(content: AppIconArt().frame(width: side, height: side))
    r.scale = 1
    return r.nsImage
}

@MainActor
func writeIconset(to dir: URL) throws {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for base in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let r = ImageRenderer(content: AppIconArt().frame(width: CGFloat(base), height: CGFloat(base)))
            r.scale = CGFloat(scale)
            guard let cg = r.cgImage else { continue }
            let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
            try NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent(name))
        }
    }
}

let options = LaunchOptions()
let app = NSApplication.shared

if let dir = options["render-icon"] {
    MainActor.assumeIsolated {
        do { try writeIconset(to: URL(fileURLWithPath: dir)); print("iconset: \(dir)") } catch { print("icon failed: \(error)"); exit(1) }
    }
    exit(0)
}

if let dir = options["snapshot"] {
    let sizes = options["sizes"] ?? "1280x800@2,1512x982@2"
    let only = options["only"]
    let appearance = options["appearance"] ?? "all"
    MainActor.assumeIsolated { SFType.registerFonts() }
    Task { @MainActor in
        await Snapshotter(outDir: URL(fileURLWithPath: dir), sizes: sizes, only: only, appearance: appearance).run()
        exit(0)
    }
    app.setActivationPolicy(.prohibited)
    app.run()
} else {
    // Follows the system appearance (VISUAL §9); `--appearance dark|light` forces one.
    switch options["appearance"] ?? "system" {
    case "light": app.appearance = NSAppearance(named: .aqua)
    case "dark": app.appearance = NSAppearance(named: .darkAqua)
    default: break
    }
    let delegate = MainActor.assumeIsolated { AppDelegate(options: options) }
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
