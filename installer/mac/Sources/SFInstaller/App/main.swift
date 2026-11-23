import SwiftUI
import AppKit
import SFInstallKit

// SiliconForest Installer
//
//   SFInstaller                       fullscreen, dry run on the simulated J293 disk
//   SFInstaller --windowed            a normal window (development)
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
func makeModel(_ o: LaunchOptions) -> InstallerModel {
    if o.has("real") {
        return InstallerModel(mode: .readOnly, backend: RealDiskBackend(), fixtureName: "this Mac")
    }
    let name = o["fixture"] ?? "j293-512"
    let fixture = (try? DiskFixture.named(name)) ?? (try! DiskFixture.named("j293-512"))
    var failures: [FailureInjection] = []
    if let s = o["fail-step"], let step = StepID(rawValue: s) { failures.append(FailureInjection(step: step, atFraction: 0.45)) }
    let backend = SimulatedDiskBackend(fixture: fixture, timeScale: Double(o["speed"] ?? "1") ?? 1, failures: failures)
    return InstallerModel(mode: .dryRun, backend: backend, fixtureName: name)
}

/// Supplies theme and screen size from the live environment.
struct AppRoot: View {
    var model: InstallerModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            RootView(model: model)
                .environment(\.theme, Theme(isDark: scheme == .dark))
                .environment(\.screenSize, geo.size)
        }
        .ignoresSafeArea()
        .task { await model.load() }
    }
}

final class FullscreenWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let options: LaunchOptions
    var model: InstallerModel!
    var window: NSWindow!

    init(options: LaunchOptions) { self.options = options }

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = makeModel(options)
        NSApp.applicationIconImage = renderIcon(side: 512)
        buildMenu()
        let host = NSHostingView(rootView: AppRoot(model: model))

        if options.has("windowed") {
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.center()
        } else {
            // Like the macOS installer: one borderless window covering the whole display, Dock and
            // menu bar hidden.
            let screen = NSScreen.main ?? NSScreen.screens[0]
            window = FullscreenWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
            window.setFrame(screen.frame, display: true)
            window.collectionBehavior = [.fullScreenNone, .canJoinAllSpaces]
            window.isMovable = false
            NSApp.presentationOptions = [.hideDock, .hideMenuBar, .disableHideApplication]
        }
        window.contentView = host
        window.title = "SiliconForest Installer"
        window.backgroundColor = .black
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model.quitConfirmed { return .terminateNow }
        model.requestQuit()
        return .terminateCancel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit SiliconForest Installer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        // Edit menu so ⌘C/⌘V/⌘A work in the name field.
        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        NSApp.mainMenu = main
    }
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
    Task { @MainActor in
        await Snapshotter(outDir: URL(fileURLWithPath: dir), sizes: sizes, only: only, appearance: appearance).run()
        exit(0)
    }
    app.setActivationPolicy(.prohibited)
    app.run()
} else {
    // Dark first (Canopy); `--appearance light` for Clearing, `--appearance system` to follow macOS.
    switch options["appearance"] ?? "dark" {
    case "light": app.appearance = NSAppearance(named: .aqua)
    case "system": break
    default: app.appearance = NSAppearance(named: .darkAqua)
    }
    let delegate = MainActor.assumeIsolated { AppDelegate(options: options) }
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
