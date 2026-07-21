import SwiftUI
import AppKit

public struct SettingsView: View {
    @EnvironmentObject private var localization: LocalizationManager

    public init() {}

    public var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label(L("settings.general"), systemImage: "gearshape") }

            BackupsSettingsTab()
                .tabItem { Label(L("settings.backups"), systemImage: "clock.arrow.circlepath") }

            DiagnosticsSettingsTab()
                .tabItem { Label(L("settings.diagnostics"), systemImage: "stethoscope") }

            LogsSettingsTab()
                .tabItem { Label(L("settings.logs"), systemImage: "text.alignleft") }

            AboutSettingsTab()
                .tabItem { Label(L("settings.about"), systemImage: "info.circle") }
        }
        .frame(minWidth: 640, minHeight: 500)
        .padding()
    }
}

// MARK: - General

public enum MirrorDefaults {
    public static let node = "https://nodejs.org/dist/"
    public static let python = "https://www.python.org/ftp/python/"
    public static let go = "https://go.dev/dl/"
    public static let java = "https://download.oracle.com/java/"
}

struct GeneralSettingsTab: View {
    @EnvironmentObject private var localization: LocalizationManager
    @AppStorage("colorSchemePreference") private var colorSchemePreference: String = "system"
    @AppStorage("nodeMirror") private var nodeMirror: String = MirrorDefaults.node
    @AppStorage("pythonMirror") private var pythonMirror: String = MirrorDefaults.python
    @AppStorage("goMirror") private var goMirror: String = MirrorDefaults.go
    @AppStorage("javaMirror") private var javaMirror: String = MirrorDefaults.java
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = true

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

            Section(L("settings.notifications")) {
                Toggle(L("settings.notifications.toggle"), isOn: $notificationsEnabled)
                Text(L("settings.notifications.hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L("settings.mirrors")) {
                TextField(L("settings.nodeMirror"), text: $nodeMirror)
                TextField(L("settings.pythonMirror"), text: $pythonMirror)
                TextField(L("settings.goMirror"), text: $goMirror)
                TextField(L("settings.javaMirror"), text: $javaMirror)

                HStack {
                    Spacer()
                    Button(L("settings.resetDefaults")) {
                        resetDefaults()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func resetDefaults() {
        nodeMirror = MirrorDefaults.node
        pythonMirror = MirrorDefaults.python
        goMirror = MirrorDefaults.go
        javaMirror = MirrorDefaults.java
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
    private var appVersion: String {
        if let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String, !v.isEmpty {
            return v
        }
        return "1.0.0"
    }

    private let githubURL = URL(string: "https://github.com/EnvMatrix/EnvMatrix")!

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .padding(.top, 8)

            Text("EnvMatrix")
                .font(.largeTitle.bold())

            Text(String(format: L("settings.version"), appVersion))
                .foregroundStyle(.secondary)

            Text(L("settings.aboutDescription"))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)

            Button {
                NSWorkspace.shared.open(githubURL)
            } label: {
                Label(L("settings.viewGitHub"), systemImage: "link")
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
