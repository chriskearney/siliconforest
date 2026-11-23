import SwiftUI
import SFInstallKit

// MARK: - Manage

struct ManageScreen: View {
    @Bindable var model: InstallerModel
    @Environment(\.theme) private var theme

    var body: some View {
        PanelScaffold(symbol: "slider.horizontal.3", title: "Manage SiliconForest",
                      subtitle: "Installations found on this Mac’s internal disk.") {
            VStack(spacing: 22) {
                ForEach(model.existingInstalls) { install in
                    InstallCard(install: install, selected: model.selectedInstall?.id == install.id) {
                        model.selectedInstall = install
                        model.go(.uninstallReview)
                    }
                }
                if let install = model.selectedInstall ?? model.existingInstalls.first, let profile = model.profile {
                    HStack(spacing: 12) {
                        DetailTile(title: "Startup security", value: "Permissive", detail: "For \(install.name) only")
                        DetailTile(title: "Startup firmware", value: "macOS \(profile.support.preferredStubFirmware ?? "13.5")", detail: "Stub in \(install.stub.identifier)")
                        DetailTile(title: "Kernel", value: "\(profile.kernel.kexts.count) drivers", detail: "\(profile.kernel.bootArgs.count) boot arguments")
                        DetailTile(title: "Default system", value: "macOS", detail: "Hold power to choose")
                    }
                }
                if let disk = model.disk {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("INTERNAL DISK").font(.system(size: 11, weight: .bold)).tracking(1.2).foregroundStyle(theme.textTertiary)
                        PartitionBar(disk: disk, constraints: nil, size: .constant(0), editable: false, height: 64, asIs: true)
                        HStack(spacing: 14) {
                            Text("\(disk.mediaName.replacingOccurrences(of: "APPLE SSD ", with: "Internal SSD ")) · \(Bytes.format(disk.size))")
                                .font(Typo.caption).foregroundStyle(theme.textTertiary)
                            Spacer()
                            Legend()
                        }
                    }
                }
            }
        } footer: {
            Button("Back") { model.back() }.buttonStyle(SecondaryButtonStyle()).keyboardShortcut("[", modifiers: .command)
            Spacer()
            Button("Install Another Copy") { model.go(.compatibility) }.buttonStyle(SecondaryButtonStyle())
        }
    }
}

struct InstallCard: View {
    var install: SiliconForestInstall
    var selected: Bool
    var uninstall: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            AppIconArt().frame(width: 76, height: 76)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text(install.name).font(.system(size: 20, weight: .semibold)).foregroundStyle(theme.text)
                    if let v = install.version {
                        Text(v).font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.mint)
                            .padding(.horizontal, 8).frame(height: 20).background(Capsule().fill(theme.mint.opacity(0.14)))
                    }
                    if !install.isComplete {
                        Text("Incomplete").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.gold)
                            .padding(.horizontal, 8).frame(height: 20).background(Capsule().fill(theme.gold.opacity(0.14)))
                    }
                }
                Text("\(Bytes.format(install.totalBytes)) on the internal disk\(install.installedAt.map { " · installed \(Self.pretty($0))" } ?? "")")
                    .font(Typo.callout).foregroundStyle(theme.textSecondary)
                HStack(spacing: 8) {
                    part("Startup", install.stub)
                    if let b = install.boot { part(b.name ?? "Boot", b) }
                    if let r = install.root { part("System", r) }
                }
                .padding(.top, 4)
            }
            Spacer()
            Button(action: uninstall) { Label("Uninstall…", systemImage: "trash") }
                .buttonStyle(SecondaryButtonStyle(destructive: true))
        }
        .padding(22)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(theme.card)
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(selected ? theme.mint.opacity(0.5) : theme.cardStroke, lineWidth: 1)))
        .accessibilityElement(children: .contain)
    }

    private func part(_ label: String, _ p: Partition) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.text)
            Text("\(p.identifier) · \(Bytes.format(p.size))").font(Typo.number(11.5, weight: .medium)).foregroundStyle(theme.textSecondary)
        }
        .padding(.horizontal, 10).frame(height: 24)
        .background(Capsule().fill(theme.well))
    }

    static func pretty(_ iso: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: iso) else { return iso }
        let out = DateFormatter(); out.dateStyle = .long
        return out.string(from: d)
    }
}

// MARK: - Uninstall review

struct UninstallReviewScreen: View {
    @Bindable var model: InstallerModel
    var holdPreview: Double? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        let install = model.selectedInstall ?? model.existingInstalls.first
        PanelScaffold(symbol: "trash", title: "Uninstall \(install?.name ?? "SiliconForest")?",
                      subtitle: "Its partitions and everything stored in them are erased. macOS gets the space back.",
                      tint: theme.coral) {
            if let disk = model.disk, let install {
                HStack(alignment: .top, spacing: 30) {
                    VStack(alignment: .leading, spacing: 18) {
                        BeforeAfter(label: "Now", disk: disk, constraints: nil, size: 0, asIs: true)
                        BeforeAfter(label: "After", disk: disk, constraints: nil, size: 0, asIs: false, reclaim: install)
                            .padding(.bottom, 4)
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(theme.coral)
                            Text("This can’t be undone. Copy anything you want to keep out of \(install.name) first.")
                                .font(Typo.callout).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.coral.opacity(0.08))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.coral.opacity(0.3), lineWidth: 1)))
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 0) {
                        if let r = install.root {
                            SummaryRow(symbol: "internaldrive", title: "System volume", value: "\(r.identifier) · \(Bytes.format(r.size))", detail: "Erased, with your files in \(install.name)", tint: theme.coral)
                            divider
                        }
                        if let b = install.boot {
                            SummaryRow(symbol: "memorychip", title: b.name ?? "Boot", value: "\(b.identifier) · \(Bytes.format(b.size))", detail: "Kernel, second stage, Wi-Fi firmware", tint: theme.coral)
                            divider
                        }
                        SummaryRow(symbol: "shippingbox", title: "Startup container", value: "\(install.stub.identifier) · \(Bytes.format(install.stub.size))", detail: "And its entry in the startup picker", tint: theme.coral)
                        divider
                        SummaryRow(symbol: "arrow.up.left.and.arrow.down.right", title: "macOS", value: "\(Bytes.format(disk.macOSPartition?.size ?? 0)) → \(Bytes.format((disk.macOSPartition?.size ?? 0) + install.totalBytes + disk.freeAfter(install.partitions.last?.identifier ?? "")))", detail: "Grows back. Nothing in macOS is touched.")
                    }
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(theme.card)
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(theme.cardStroke, lineWidth: 1)))
                    .frame(width: 430)
                }
            }
        } footer: {
            Button("Back") { model.back() }.buttonStyle(SecondaryButtonStyle()).keyboardShortcut("[", modifiers: .command)
            Spacer()
            Text("Press and hold to erase").font(Typo.callout).foregroundStyle(theme.textTertiary).padding(.trailing, 6)
            HoldButton(title: "Hold to Uninstall", holdingTitle: "Keep holding…", symbol: "trash", duration: 2.0, destructive: true, previewProgress: holdPreview) {
                model.startUninstall()
            }
        }
    }

    private var divider: some View { Rectangle().fill(theme.hairline).frame(height: 1).padding(.leading, 56) }
}

// MARK: - Uninstall done

struct UninstallDoneScreen: View {
    var model: InstallerModel
    @Environment(\.theme) private var theme

    var body: some View {
        let name = model.plan?.options.installName ?? "SiliconForest"
        VStack(spacing: 0) {
            ZStack {
                Circle().strokeBorder(theme.mint.opacity(0.25), lineWidth: 1).frame(width: 150, height: 150)
                Circle().strokeBorder(theme.mint.opacity(0.12), lineWidth: 1).frame(width: 196, height: 196)
                Image(systemName: "checkmark").font(.system(size: 52, weight: .light)).foregroundStyle(theme.mint)
                    .shadow(color: theme.mint.opacity(0.5), radius: 14)
            }
            .padding(.bottom, 26)
            Text("\(name) has been removed")
                .font(.system(size: 46, weight: .light)).tracking(-0.4).foregroundStyle(theme.text)
                .accessibilityAddTraits(.isHeader)
            Text("macOS has its \(Bytes.format(model.plan?.macOSSizeAfter ?? 0)) back. Nothing in macOS was changed.")
                .font(.system(size: 18)).foregroundStyle(theme.textSecondary).padding(.top, 10)
            if let disk = model.disk {
                GlassPanel(camera: model.screen.camera, cornerRadius: 22) {
                    VStack(alignment: .leading, spacing: 14) {
                        BeforeAfter(label: "Internal disk now", disk: disk, constraints: nil, size: 0, asIs: true)
                        HStack(spacing: 18) {
                            ForEach(model.plan?.steps.filter { [.removeRoot, .removeBoot, .removeStub, .growMacOS].contains($0.id) } ?? []) { s in
                                HStack(spacing: 7) {
                                    StatusGlyph(kind: .pass, size: 16)
                                    Text(Self.short(s.id)).font(.system(size: 12.5)).foregroundStyle(theme.textSecondary).fixedSize()
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .padding(24)
                    .frame(width: 760)
                }
                .padding(.top, 34)
            }
            Button("Done") { model.go(.welcome, forward: false) }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .padding(.top, 34)
            if model.isDryRun {
                Text("Dry run complete. No disk was changed.").font(Typo.callout).foregroundStyle(theme.copper).padding(.top, 14)
            }
        }
        .padding(.bottom, 20)
    }

    static func short(_ id: StepID) -> String {
        switch id {
        case .removeRoot: return "System volume removed"
        case .removeBoot: return "SFBOOT removed"
        case .removeStub: return "Startup container removed"
        case .growMacOS: return "macOS grown back"
        default: return id.rawValue
        }
    }
}

// MARK: - Failure / rollback

struct FailureScreen: View {
    @Bindable var model: InstallerModel
    @Environment(\.theme) private var theme

    var body: some View {
        let clean = model.rollbackClean
        let isUninstall = model.plan?.kind == .uninstall
        let title: String = {
            if model.rollingBack { return "Undoing changes…" }
            if clean == false { return isUninstall ? "Uninstall stopped partway" : "Rollback needs attention" }
            return isUninstall ? "Uninstall stopped safely" : "Installation stopped safely"
        }()
        let subtitle: String = {
            if model.rollingBack { return "Something went wrong. The installer is putting your disk back exactly as it was." }
            if clean == false { return "Some changes couldn’t be undone automatically. Your macOS data is untouched; the journal lists what’s left." }
            return "Something went wrong, so the installer undid every change. Your Mac is exactly as it was."
        }()
        PanelScaffold(symbol: model.rollingBack ? "arrow.uturn.backward" : (clean == false ? "exclamationmark.triangle" : "checkmark.shield"),
                      title: title, subtitle: subtitle, tint: clean == false ? theme.coral : theme.copper) {
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("WHAT HAPPENED").font(.system(size: 11, weight: .bold)).tracking(1.2).foregroundStyle(theme.textTertiary)
                        if let i = model.failedStep, let p = model.plan {
                            Text("Step \(i + 1): \(p.steps[i].title)").font(.system(size: 16, weight: .semibold)).foregroundStyle(theme.text)
                        }
                        Text(model.failureMessage ?? "Unknown error")
                            .font(Typo.mono).foregroundStyle(theme.coral)
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.well))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("JOURNAL").font(.system(size: 11, weight: .bold)).tracking(1.2).foregroundStyle(theme.textTertiary)
                        Text(model.journalURL.map { "~/Library/Application Support/SiliconForest Installer/Journals/\($0.lastPathComponent)" } ?? "—")
                            .font(Typo.monoSmall).foregroundStyle(theme.textSecondary).lineLimit(2)
                        Text("Every command and checkpoint is recorded there. Attach it if you report the problem.")
                            .font(Typo.callout).foregroundStyle(theme.textTertiary).fixedSize(horizontal: false, vertical: true)
                    }
                    if let disk = model.disk, model.rollbackClean != nil {
                        BeforeAfter(label: model.rollbackClean == true ? "Your disk now (as before)" : "Your disk now", disk: disk, constraints: nil, size: 0, asIs: true)
                            .padding(.top, 6)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("ROLLBACK").font(.system(size: 11, weight: .bold)).tracking(1.2).foregroundStyle(theme.textTertiary)
                        Spacer()
                        if model.rollingBack { Spinner(size: 14) } else if clean == true {
                            Label("Clean", systemImage: "checkmark").font(Typo.caption).foregroundStyle(theme.mint)
                        }
                    }
                    .padding(.horizontal, 10).padding(.bottom, 8)
                    if let p = model.plan {
                        ForEach(Array(p.steps.enumerated()), id: \.offset) { i, s in
                            if model.stepStates.indices.contains(i), model.stepStates[i] != .pending {
                                StepRow(title: s.title, state: model.stepStates[i], fraction: nil)
                            }
                        }
                    }
                }
                .padding(16)
                .frame(width: 420, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(theme.card)
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(theme.cardStroke, lineWidth: 1)))
            }
        } footer: {
            Button { withAnimation { model.logOpen.toggle() } } label: { Label("Show Log", systemImage: "text.alignleft") }
                .buttonStyle(SecondaryButtonStyle())
            Spacer()
            Button("Quit") { model.terminate() }.buttonStyle(SecondaryButtonStyle()).disabled(model.rollingBack)
            Button("Try Again") { model.retryAfterFailure() }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(model.rollingBack || model.rollbackClean == false)
        }
        .overlay(alignment: .bottom) {
            if model.logOpen {
                LogDrawer(lines: model.log, journal: model.journalURL).padding(.bottom, 76).transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}


struct DetailTile: View {
    var title: String
    var value: String
    var detail: String
    @Environment(\.theme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(.system(size: 10.5, weight: .bold)).tracking(1.1).foregroundStyle(theme.textTertiary)
            Text(value).font(.system(size: 16, weight: .semibold)).foregroundStyle(theme.text)
            Text(detail).font(Typo.caption).foregroundStyle(theme.textSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.card)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(theme.cardStroke, lineWidth: 1)))
        .accessibilityElement(children: .combine)
    }
}
