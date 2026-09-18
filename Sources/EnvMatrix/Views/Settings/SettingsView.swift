import SwiftUI
import AppKit

public enum SettingsTab: String, Hashable {
    case general, backups, history, diagnostics, logs, about
}

public struct SettingsView: View {
    @EnvironmentObject private var localization: LocalizationManager
    @State private var selectedTab: SettingsTab = .general

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                title: L("nav.settings"),
                subtitle: L("settings.subtitle"),
                systemImage: NavigationItem.settings.systemImage,
                tint: NavigationItem.settings.tint
            )
            tabs
        }
        .onReceive(NotificationCenter.default.publisher(for: .envMatrixOpenDiagnostics)) { _ in
            selectedTab = .diagnostics
        }
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsTab()
                .tabItem { Label(L("settings.general"), systemImage: "gearshape") }
                .tag(SettingsTab.general)

            BackupsSettingsTab()
                .tabItem { Label(L("settings.backups"), systemImage: "clock.arrow.circlepath") }
                .tag(SettingsTab.backups)

            HistorySettingsTab()
                .tabItem { Label(L("settings.history"), systemImage: "list.bullet.rectangle") }
                .tag(SettingsTab.history)

            DiagnosticsSettingsTab()
                .tabItem { Label(L("settings.diagnostics"), systemImage: "stethoscope") }
                .tag(SettingsTab.diagnostics)

            LogsSettingsTab()
                .tabItem { Label(L("settings.logs"), systemImage: "text.alignleft") }
                .tag(SettingsTab.logs)

            AboutSettingsTab()
                .tabItem { Label(L("settings.about"), systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(minWidth: 640, minHeight: 500)
        .padding([.horizontal, .bottom])
    }
}

// MARK: - General

public enum MirrorDefaults {
    public static let node = DownloadMirrors.nodeDefault
    public static let go = DownloadMirrors.goDefault
}

struct GeneralSettingsTab: View {
    @EnvironmentObject private var localization: LocalizationManager
    @AppStorage("colorSchemePreference") private var colorSchemePreference: String = "system"
    @AppStorage(DownloadMirrors.nodeKey) private var nodeMirror: String = MirrorDefaults.node
    @AppStorage(DownloadMirrors.goKey) private var goMirror: String = MirrorDefaults.go
    @State private var presetToApply: MirrorPresetProfile? = nil
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = true
    @AppStorage(UpdateChecker.autoCheckKey) private var autoCheckUpdates: Bool = true
    @AppStorage(MenuBarPreference.key) private var menuBarEnabled: Bool = true

    var body: some View {
        Form {
            Section(L("settings.appearance")) {
                Picker(L("settings.colorScheme"), selection: $colorSchemePreference) {
                    Text(L("settings.system")).tag("system")
                    Text(L("settings.light")).tag("light")
                    Text(L("settings.dark")).tag("dark")
                }
                .pickerStyle(.segmented)
            }

            Section(L("settings.language")) {
                Picker(L("settings.languageLabel"), selection: Binding(
                    get: { localization.language },
                    set: { localization.language = $0 }
                )) {
                    Text(L("settings.system")).tag(AppLanguage.system)
                    Text("English").tag(AppLanguage.en)
                    Text("中文").tag(AppLanguage.zh)
                }
                .pickerStyle(.segmented)
            }

            Section(L("settings.menuBar")) {
                Toggle(L("settings.menuBar.toggle"), isOn: $menuBarEnabled)
                Text(L("settings.menuBar.hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L("settings.notifications")) {
                Toggle(L("settings.notifications.toggle"), isOn: $notificationsEnabled)
                Text(L("settings.notifications.hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L("settings.updates")) {
                Toggle(L("settings.updates.autoCheck"), isOn: $autoCheckUpdates)
                Text(L("settings.updates.hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(L("settings.showOnboarding")) {
                    NotificationCenter.default.post(name: .envMatrixShowOnboarding, object: nil)
                }
            }

            Section(L("settings.mirrorPresets")) {
                HStack(spacing: 10) {
                    Button {
                        presetToApply = .chinaMainland
                    } label: {
                        Label(L("mirrorPreset.chinaMainland.title"), systemImage: "bolt.horizontal.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        presetToApply = .official
                    } label: {
                        Label(L("mirrorPreset.official.title"), systemImage: "globe")
                    }
                }
                Text(L("settings.mirrorPresets.hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L("settings.mirrors")) {
                TextField(L("settings.nodeMirror"), text: $nodeMirror)
                TextField(L("settings.goMirror"), text: $goMirror)
                Text(L("settings.mirrors.hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Spacer()
                    Button(L("settings.resetDefaults")) {
                        resetDefaults()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .sheet(item: $presetToApply) { profile in
            MirrorPresetSheet(profile: profile, onDone: { presetToApply = nil })
                .environmentObject(localization)
        }
    }

    private func resetDefaults() {
        nodeMirror = MirrorDefaults.node
        goMirror = MirrorDefaults.go
    }
}

// MARK: - Logs

struct LogsSettingsTab: View {
    @ObservedObject private var store = LogStore.shared

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(format: L("settings.entries"), store.entries.count))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    store.clear()
                } label: {
                    Label(L("settings.clear"), systemImage: "trash")
                }
                .disabled(store.entries.isEmpty)
            }
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if store.entries.isEmpty {
                        Text(L("settings.noLogs"))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    } else {
                        ForEach(store.entries) { entry in
                            row(for: entry)
                        }
                    }
                }
                .padding(6)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
            )
        }
        .padding()
    }

    @ViewBuilder
    private func row(for entry: LogEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(Self.timeFormatter.string(from: entry.timestamp))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            Image(systemName: entry.level.systemImage)
                .foregroundStyle(color(for: entry.level))
            Text(entry.message)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
    }

    private func color(for level: LogLevel) -> Color {
        switch level {
        case .info: return .accentColor
        case .warning: return .orange
        case .error: return .red
        }
    }
}

// MARK: - About

struct AboutSettingsTab: View {
    @ObservedObject private var checker = UpdateChecker.shared
    @EnvironmentObject private var localization: LocalizationManager

    private let githubURL = URL(string: "https://github.com/\(GitHubUpdateCheckService.repository)")!
    private let issuesURL = URL(string: "https://github.com/\(GitHubUpdateCheckService.repository)/issues/new/choose")!

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .padding(.top, 8)

            Text("EnvMatrix")
                .font(.largeTitle.bold())

            Text(String(format: L("settings.version"), checker.currentVersion))
                .foregroundStyle(.secondary)

            Text(L("settings.aboutDescription"))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)

            updateBlock

            HStack(spacing: 12) {
                Button {
                    NSWorkspace.shared.open(githubURL)
                } label: {
                    Label(L("settings.viewGitHub"), systemImage: "link")
                }
                .buttonStyle(.borderedProminent)
                Button {
                    NSWorkspace.shared.open(issuesURL)
                } label: {
                    Label(L("settings.reportIssue"), systemImage: "ladybug")
                }
                Button {
                    NSWorkspace.shared.open(GitHubUpdateCheckService.releasesPage)
                } label: {
                    Label(L("settings.releaseNotes"), systemImage: "doc.text")
                }
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var updateBlock: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                switch checker.state {
                case .idle:
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.secondary)
                    Text(L("update.state.idle"))
                        .foregroundStyle(.secondary)
                case .checking:
                    ProgressView().controlSize(.small)
                    Text(L("update.state.checking"))
                        .foregroundStyle(.secondary)
                case .upToDate(let latest):
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(String(format: L("update.state.upToDate"), latest))
                case .available(let release):
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.blue)
                    Text(String(format: L("update.state.available"), release.version))
                    Button {
                        NSWorkspace.shared.open(release.url)
                    } label: {
                        Label(L("update.banner.open"), systemImage: "arrow.up.right.square")
                    }
                    .controlSize(.small)
                case .failed(let msg):
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(msg)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .font(.callout)

            HStack(spacing: 12) {
                Button {
                    checker.clearSkipped()
                    Task { await checker.check() }
                } label: {
                    Label(L("update.checkNow"), systemImage: "arrow.clockwise")
                }
                .disabled(checker.state == .checking)
                if let last = checker.lastCheckedAt {
                    Text(String(format: L("update.lastChecked"),
                                last.formatted(date: .abbreviated, time: .shortened)))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: 480)
        .background(Color.subtleFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
