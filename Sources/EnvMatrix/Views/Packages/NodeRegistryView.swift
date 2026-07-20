import SwiftUI
import AppKit

public struct NodeRegistryView: View {
    @StateObject private var vm = NodeRegistryViewModel()
    @State private var pendingPreset: NodeRegistryMirror? = nil
    @State private var showCustomConfirm: Bool = false

    public init() {}

    public var body: some View {
        Group {
            if !vm.npmAvailable {
                NpmMissingView()
            } else {
                mainContent
            }
        }
        .task { await vm.load() }
        .confirmationDialog(
            L("nodeRepo.registry.confirmApply"),
            isPresented: Binding(
                get: { pendingPreset != nil },
                set: { newValue in if !newValue { pendingPreset = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L("common.confirm")) {
                if let preset = pendingPreset {
                    pendingPreset = nil
                    Task { await vm.applyPreset(preset) }
                }
            }
            Button(L("common.cancel"), role: .cancel) {
                pendingPreset = nil
            }
        } message: {
            if let preset = pendingPreset {
                Text("\(preset.name)\n\(preset.url)")
            }
        }
        .confirmationDialog(
            L("nodeRepo.registry.confirmApply"),
            isPresented: $showCustomConfirm,
            titleVisibility: .visible
        ) {
            Button(L("common.confirm")) {
                showCustomConfirm = false
                Task { await vm.applyCustomURL() }
            }
            Button(L("common.cancel"), role: .cancel) {
                showCustomConfirm = false
            }
        } message: {
            Text(vm.customURL)
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            banners
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    presetsSection
                    customSection
                }
                .padding()
            }
        }
    }

    // MARK: - Banners

    @ViewBuilder
    private var banners: some View {
        if let err = vm.errorMessage {
            banner(text: err, color: .red, icon: "exclamationmark.triangle.fill")
        }
        if let info = vm.infoMessage {
            banner(text: info, color: .green, icon: "checkmark.circle.fill")
        }
    }

    private func banner(text: String, color: Color, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(text)
                .font(.caption)
                .foregroundStyle(color)
            Spacer()
        }
        .padding(8)
        .background(color.opacity(0.08))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe")
                .foregroundStyle(.blue)
            Text(L("nodeRepo.registry.current"))
                .bold()
            Text(vm.currentRegistry)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            Button {
                copyToPasteboard(vm.currentRegistry)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help(vm.currentRegistry)
            Spacer()
            Button {
                Task { await vm.load() }
            } label: {
                Label(L("common.refresh"), systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(vm.isLoading)
        }
    }

    // MARK: - Presets

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("nodeRepo.registry.presets"))
                .font(.headline)
            let columns = [GridItem(.adaptive(minimum: 260), spacing: 8)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(vm.presets) { mirror in
                    presetCard(mirror)
                }
            }
        }
    }

    private func presetCard(_ mirror: NodeRegistryMirror) -> some View {
        Button {
            pendingPreset = mirror
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "network")
                    .foregroundStyle(.blue)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 3) {
                    Text(mirror.name)
                        .font(.body.bold())
                    Text(mirror.url)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
                if mirror.url == vm.currentRegistry {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Custom

    private var customSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("nodeRepo.registry.custom"))
                .font(.headline)
            HStack {
                TextField("https://…", text: $vm.customURL)
                    .textFieldStyle(.roundedBorder)
                Button(L("nodeRepo.registry.apply")) {
                    showCustomConfirm = true
                }
                .disabled(!isCustomValid)
            }
        }
    }

    private var isCustomValid: Bool {
        let trimmed = vm.customURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
    }

    // MARK: - Utils

    private func copyToPasteboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}
