import SwiftUI
import AppKit

public struct SettingsView: View {
    public init() {}

    public var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }

            LogsSettingsTab()
                .tabItem { Label("Logs", systemImage: "text.alignleft") }

            AboutSettingsTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(minWidth: 560, minHeight: 460)
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
    @AppStorage("colorSchemePreference") private var colorSchemePreference: String = "system"
    @AppStorage("nodeMirror") private var nodeMirror: String = MirrorDefaults.node
    @AppStorage("pythonMirror") private var pythonMirror: String = MirrorDefaults.python
    @AppStorage("goMirror") private var goMirror: String = MirrorDefaults.go
    @AppStorage("javaMirror") private var javaMirror: String = MirrorDefaults.java

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Color Scheme", selection: $colorSchemePreference) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
            }

            Section("Mirror Sources") {
                TextField("Node.js Mirror", text: $nodeMirror)
                TextField("Python Mirror", text: $pythonMirror)
                TextField("Go Mirror", text: $goMirror)
                TextField("Java Mirror", text: $javaMirror)

                HStack {
                    Spacer()
                    Button("Reset to Defaults") {
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
                Text("\(store.entries.count) entries")
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    store.clear()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .disabled(store.entries.isEmpty)
            }
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if store.entries.isEmpty {
                        Text("No log entries.")
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

            Text("Version \(appVersion)")
                .foregroundStyle(.secondary)

            Text("A unified macOS control panel for managing developer runtimes and AI development environments.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)

            Button {
                NSWorkspace.shared.open(githubURL)
            } label: {
                Label("View on GitHub", systemImage: "link")
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
