import SwiftUI
import SFInstallKit

struct RootView: View {
    @Bindable var model: InstallerModel
    @Environment(\.theme) private var theme
    @Environment(\.screenSize) private var screenSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        let w = screenSize.width, h = screenSize.height
        let panelW = min(1060, w - 150)
        let panelH = min(640, h - 64 - 52 - 24)
        ZStack {
            ForestBackdrop(camera: model.screen.camera)
                .animation(reduceMotion ? nil : .easeInOut(duration: 1.6), value: model.screen)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                TopBar(model: model)
                    .frame(height: 64)
                Spacer(minLength: 0)
                ZStack {
                    if model.screen.usesPanel {
                        GlassPanel(camera: model.screen.camera) {
                            ZStack {
                                panelContent
                                    .id(model.screen)
                                    .transition(stepTransition)
                            }
                            .frame(width: panelW, height: panelH)
                            .clipped()
                        }
                        .frame(width: panelW, height: panelH)
                        .transition(.opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.97)))
                    } else {
                        heroContent
                            .id(model.screen)
                            .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 14)))
                    }
                }
                Spacer(minLength: 0)
                BottomHints(model: model)
                    .frame(height: 52)
            }

            if model.showQuitConfirm {
                QuitOverlay(model: model)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .frame(width: w, height: h)
        .coordinateSpace(name: "screen")
        .background(theme.isDark ? Color.black : Color(hex: 0xDCE7E0))
        .onKeyPress(.escape) {
            if model.showQuitConfirm { withAnimation { model.showQuitConfirm = false } } else if model.logOpen { withAnimation { model.logOpen = false } } else { model.requestQuit() }
            return .handled
        }
    }

    private var stepTransition: AnyTransition {
        if reduceMotion || isSnapshot { return .opacity }
        let d: CGFloat = model.forward ? 1 : -1
        return .asymmetric(insertion: .offset(x: 48 * d).combined(with: .opacity),
                           removal: .offset(x: -48 * d).combined(with: .opacity))
    }

    @ViewBuilder private var panelContent: some View {
        switch model.screen {
        case .compatibility: CompatibilityScreen(model: model)
        case .beforeYouBegin: BeforeYouBeginScreen(model: model)
        case .disk: DiskScreen(model: model, showTag: model.snapshotDiskTag)
        case .options: OptionsScreen(model: model, nameFocused: model.snapshotNameFocus)
        case .review: ReviewScreen(model: model, holdPreview: model.snapshotHold)
        case .installing, .uninstalling: RunScreen(model: model)
        case .recovery: RecoveryScreen(model: model)
        case .manage: ManageScreen(model: model)
        case .uninstallReview: UninstallReviewScreen(model: model, holdPreview: model.snapshotHold)
        case .failure: FailureScreen(model: model)
        case .welcome, .done, .uninstallDone: EmptyView()
        }
    }

    @ViewBuilder private var heroContent: some View {
        switch model.screen {
        case .welcome: WelcomeScreen(model: model)
        case .done: DoneScreen(model: model)
        case .uninstallDone: UninstallDoneScreen(model: model)
        default: EmptyView()
        }
    }
}

// MARK: - Chrome

struct TopBar: View {
    var model: InstallerModel
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    BrandMark.mint(theme, glow: false).frame(height: 21)
                    Text("SiliconForest").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.text)
                        + Text("  Installer").font(.system(size: 14, weight: .regular)).foregroundStyle(theme.textSecondary)
                }
                .opacity(model.screen == .welcome ? 0 : 1)
                .accessibilityElement(children: .combine)
                Spacer()
                ModeBadge(mode: model.mode)
                Button { model.requestQuit() } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(theme.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(theme.isDark ? Color.black.opacity(0.3) : Color.white.opacity(0.55)).overlay(Circle().strokeBorder(theme.hairline, lineWidth: 1)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Quit installer")
            }
            if let i = model.screen.flowIndex {
                FlowIndicator(index: i)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 28)
    }
}

struct BottomHints: View {
    var model: InstallerModel
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 18) {
            if model.canGoBack { hint(["⌘", "["], "Back") }
            hint(["return"], model.screen == .review || model.screen == .uninstallReview ? "Hold to confirm" : "Continue")
            hint(["esc"], "Quit")
        }
        .padding(.horizontal, 14).frame(height: 32)
        .background(Capsule().fill(theme.isDark ? Color.black.opacity(0.35) : Color.white.opacity(0.55))
            .overlay(Capsule().strokeBorder(theme.hairline, lineWidth: 1)))
        .opacity(model.screen == .installing || model.screen == .uninstalling ? 0 : 1)
        .accessibilityHidden(true)
    }

    private func hint(_ keys: [String], _ label: String) -> some View {
        HStack(spacing: 5) {
            ForEach(keys, id: \.self) { KeyCap(text: $0) }
            Text(label).font(.system(size: 11.5, weight: .medium)).foregroundStyle(theme.textTertiary)
        }
    }
}

/// Every panel screen: header, content, footer with Back on the left and actions on the right.
struct PanelScaffold<Content: View, Footer: View>: View {
    var symbol: String
    var title: String
    var subtitle: String
    var tint: Color? = nil
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(symbol: symbol, title: title, subtitle: subtitle, tint: tint)
                .padding(.horizontal, 48)
                .padding(.top, 40)
                .padding(.bottom, 26)
            content
                .padding(.horizontal, 48)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Rectangle().fill(theme.hairline).frame(height: 1)
            HStack(spacing: 12) { footer }
                .padding(.horizontal, 32)
                .frame(height: 76)
        }
    }
}

struct QuitOverlay: View {
    var model: InstallerModel
    @Environment(\.theme) private var theme

    var body: some View {
        let m = model.quitMessage
        ZStack {
            Color.black.opacity(theme.isDark ? 0.5 : 0.25).ignoresSafeArea()
                .onTapGesture { withAnimation { model.showQuitConfirm = false } }
            GlassPanel(camera: model.screen.camera, cornerRadius: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        HeaderIcon(symbol: model.isBusy ? "arrow.uturn.backward" : "rectangle.portrait.and.arrow.right", tint: model.isBusy ? theme.copper : theme.mint, size: 44)
                        Text(m.title).font(Typo.title).foregroundStyle(theme.text)
                    }
                    Text(m.body).font(Typo.body).foregroundStyle(theme.textSecondary).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        Spacer()
                        Button(m.cancel) { withAnimation { model.showQuitConfirm = false } }
                            .buttonStyle(SecondaryButtonStyle())
                            .keyboardShortcut(.cancelAction)
                        Button(m.confirm) { model.confirmQuit() }
                            .buttonStyle(PrimaryButtonStyle(tint: model.isBusy ? LinearGradient(colors: [theme.copper, theme.coral], startPoint: .top, endPoint: .bottom) : nil))
                            .keyboardShortcut(.defaultAction)
                    }
                    .padding(.top, 6)
                }
                .padding(28)
                .frame(width: 470)
            }
        }
    }
}
