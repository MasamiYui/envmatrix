import SwiftUI
import AppKit

/// Three-step first-launch guide: what EnvMatrix found, PATH for shims,
/// and mirrors / preferences. Re-openable from Settings › General.
struct OnboardingSheet: View {
    static let completedKey = "onboarding.completed"

    let onFinish: () -> Void

    @EnvironmentObject private var localization: LocalizationManager
    @ObservedObject private var installed = InstalledRuntimesStore.shared
    @ObservedObject private var shims = ShimsPathStatus.shared
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = true
    @AppStorage(UpdateChecker.autoCheckKey) private var autoCheckUpdates: Bool = true
    @State private var step: Int = 0
    @State private var mirrorState: MirrorState = .idle

    private enum MirrorState: Equatable {
        case idle, applying, done(applied: Int, total: Int)
    }

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(24)
            Divider()
            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .frame(width: 600, height: 460)
        .onAppear {
            installed.refreshIfNeeded()
            shims.check()
        }
    }

    // MARK: - Steps

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0: welcomeStep
        case 1: pathStep
        default: mirrorsStep
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader(icon: "square.grid.2x2", tint: .accentColor,
                       title: L("onboarding.welcome.title"),
                       subtitle: L("onboarding.welcome.subtitle"))

            Picker(L("settings.languageLabel"), selection: Binding(
                get: { localization.language },
                set: { localization.language = $0 }
            )) {
                Text(L("settings.system")).tag(AppLanguage.system)
                Text("English").tag(AppLanguage.en)
                Text("中文").tag(AppLanguage.zh)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    if let kinds = installed.activeKinds {
                        Label(String(format: L("onboarding.welcome.found"), kinds.count), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        if !kinds.isEmpty {
                            Text(kinds.map { $0.displayName }.sorted().joined(separator: " · "))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(L("onboarding.welcome.scanning")).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            Text(L("onboarding.welcome.body"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var pathStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader(icon: "terminal.fill", tint: .orange,
                       title: L("onboarding.path.title"),
                       subtitle: L("onboarding.path.subtitle"))

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    if shims.writtenRcFile != nil || shims.isConfigured == true {
                        Label(L("onboarding.path.configured"), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        if let file = shims.writtenRcFile {
                            Text(String(format: L("shims.banner.done.title"), file.kind.displayName))
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    } else if shims.isConfigured == false {
                        Label(L("onboarding.path.missing"), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(shims.exportLine)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(8)
                            .background(Color.subtleFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        Button {
                            shims.addToShellRc()
                        } label: {
                            if shims.isWriting {
                                ProgressView().controlSize(.small)
                            } else {
                                Label(String(format: L("shims.banner.addToRc"), shims.targetRcDisplayName),
                                      systemImage: "square.and.arrow.down")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        if let err = shims.lastError {
                            Text(err).font(.caption).foregroundStyle(.red)
                        }
                    } else {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(L("onboarding.path.checking")).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            Text(L("onboarding.path.body"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var mirrorsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader(icon: "bolt.horizontal.circle.fill", tint: .blue,
                       title: L("onboarding.mirrors.title"),
                       subtitle: L("onboarding.mirrors.subtitle"))

            GroupBox {
                HStack(spacing: 12) {
                    switch mirrorState {
                    case .idle:
                        Button {
                            Task { await applyChinaPreset() }
                        } label: {
                            Label(L("mirrorPreset.chinaMainland.title"), systemImage: "bolt.horizontal.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        Text(L("onboarding.mirrors.keepOfficial"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .applying:
                        ProgressView().controlSize(.small)
                        Text(L("update.state.checking").replacingOccurrences(of: "…", with: ""))
                            .foregroundStyle(.secondary)
                    case .done(let applied, let total):
                        Label(String(format: L("mirrorPreset.summary"), applied, total), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    Spacer(minLength: 0)
                }
                .padding(4)
            }

            Toggle(L("settings.notifications.toggle"), isOn: $notificationsEnabled)
            Toggle(L("settings.updates.autoCheck"), isOn: $autoCheckUpdates)

            Text(L("onboarding.mirrors.body"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func applyChinaPreset() async {
        mirrorState = .applying
        let results = await MirrorPresetApplier().apply(.chinaMainland)
        let applied = results.filter { $0.isApplied }.count
        mirrorState = .done(applied: applied, total: results.count)
        OperationLog.shared.record(
            .registry,
            title: String(format: L("history.op.mirrorPreset"), L("mirrorPreset.chinaMainland.title")),
            detail: String(format: L("mirrorPreset.summary"), applied, results.count)
        )
    }

    // MARK: - Chrome

    private func stepHeader(icon: String, tint: Color, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.6)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title2.bold())
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(i == step ? Color.accentColor : Color.chipFill)
                        .frame(width: 7, height: 7)
                }
            }
            Text(String(format: L("onboarding.step"), step + 1, 3))
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
            Button(L("onboarding.skip"), action: finish)
                .buttonStyle(.borderless)
            if step > 0 {
                Button(L("onboarding.back")) { withAnimation { step -= 1 } }
            }
            if step < 2 {
                Button(L("onboarding.next")) { withAnimation { step += 1 } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(L("onboarding.finish"), action: finish)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        onFinish()
    }
}
