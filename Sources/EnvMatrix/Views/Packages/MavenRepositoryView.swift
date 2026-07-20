import SwiftUI

public enum MavenTab: String, CaseIterable, Identifiable {
    case mirrors
    case localArtifacts
    public var id: String { rawValue }

    var title: String {
        switch self {
        case .mirrors: return L("mavenRepo.tab.mirrors")
        case .localArtifacts: return L("mavenRepo.tab.localArtifacts")
        }
    }
}

public struct MavenRepositoryView: View {
    @StateObject private var settingsVM = MavenSettingsViewModel()
    @StateObject private var localVM = MavenLocalRepositoryViewModel()
    @EnvironmentObject private var localization: LocalizationManager
    @State private var selectedTab: MavenTab = .mirrors

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
            tabPicker
            Divider()
            Group {
                switch selectedTab {
                case .mirrors:
                    MavenMirrorsView(vm: settingsVM)
                case .localArtifacts:
                    MavenLocalArtifactsView(vm: localVM)
                }
            }
        }
        .navigationTitle(L("mavenRepo.title"))
        .task {
            settingsVM.refresh()
            localVM.refresh()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "shippingbox.fill")
                .font(.title)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("mavenRepo.title"))
                    .font(.title2.bold())
                Text(L("mavenRepo.subtitle"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                switch selectedTab {
                case .mirrors: settingsVM.refresh()
                case .localArtifacts: localVM.refresh()
                }
            } label: {
                Label(L("mavenRepo.refresh"), systemImage: "arrow.clockwise")
            }
        }
        .padding()
    }

    private var tabPicker: some View {
        HStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(MavenTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 360)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}

// MARK: - Mirrors tab (settings.xml)

struct MavenMirrorsView: View {
    @ObservedObject var vm: MavenSettingsViewModel

    var body: some View {
        VStack(spacing: 0) {
            metadataBar
            HStack {
                Spacer()
                Menu {
                    ForEach(vm.presetMirrors()) { preset in
                        Button(preset.name) { vm.applyPreset(preset) }
                    }
                } label: {
                    Label(L("mavenRepo.addPreset"), systemImage: "plus")
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 6)

            if vm.mirrors.isEmpty {
                emptyView
            } else {
                mirrorList
            }
            if let msg = vm.errorMessage {
                errorBanner(msg)
            }
        }
    }

    private var metadataBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                Text(L("mavenRepo.settingsFile"))
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(vm.settingsPath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(L("mavenRepo.empty.title"))
                .font(.title2.bold())
            Text(L("mavenRepo.empty.subtitle"))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var mirrorList: some View {
        List {
            ForEach(vm.mirrors) { mirror in
                mirrorRow(mirror)
            }
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private func mirrorRow(_ mirror: MavenMirror) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(mirror.name).font(.headline)
                    Text("[\(mirror.mirrorId)]")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if mirror.isEnabled {
                        Text(L("mavenRepo.active"))
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                    }
                }
                Text(mirror.url)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(String(format: L("mavenRepo.mirrorOfFormat"), mirror.mirrorOf))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { mirror.isEnabled },
                set: { _ in vm.toggleMirror(mirror) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            Button(role: .destructive) {
                vm.deleteMirror(mirror)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
            Spacer()
        }
        .padding(8)
        .background(Color.red.opacity(0.08))
    }
}
