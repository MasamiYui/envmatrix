import SwiftUI

public struct HostsView: View {
    @StateObject private var vm = HostsViewModel()
    @EnvironmentObject private var localization: LocalizationManager
    @State private var newProfileName: String = ""
    @State private var showNewProfileSheet: Bool = false
    @State private var showRenameSheet: Bool = false
    @State private var renameDraft: String = ""
    @State private var showApplyConfirm: Bool = false

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(minWidth: 220, maxWidth: 280)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(L("hosts.title"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showApplyConfirm = true
                } label: {
                    Label(L("hosts.applyToSystem"), systemImage: "bolt.badge.checkmark.fill")
                }
                .disabled(vm.selection == nil)
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    vm.saveProfile()
                } label: {
                    Label(L("hosts.saveProfile"), systemImage: "square.and.arrow.down")
                }
                .disabled(vm.selection == nil)
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    vm.refresh()
                } label: {
                    Label(L("hosts.refresh"), systemImage: "arrow.clockwise")
                }
            }
        }
        .task { vm.refresh() }
        .confirmationDialog(
            L("hosts.applyConfirm.title"),
            isPresented: $showApplyConfirm,
            titleVisibility: .visible
        ) {
            Button(L("hosts.applyConfirm.ok"), role: .destructive) {
                vm.applyToSystem()
            }
            Button(L("hosts.cancel"), role: .cancel) {}
        } message: {
            Text(L("hosts.applyConfirm.message"))
        }
        .sheet(isPresented: $showNewProfileSheet) {
            profileNameSheet(
                title: L("hosts.newProfile"),
                initial: "",
                onCommit: { name in
                    if !name.isEmpty { vm.createProfile(name: name) }
                    showNewProfileSheet = false
                },
                onCancel: { showNewProfileSheet = false }
            )
        }
        .sheet(isPresented: $showRenameSheet) {
            profileNameSheet(
                title: L("hosts.rename"),
                initial: renameDraft,
                onCommit: { name in
                    if !name.isEmpty { vm.renameSelectedProfile(to: name) }
                    showRenameSheet = false
                },
                onCancel: { showRenameSheet = false }
            )
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(vm.profiles, selection: $vm.selection) { profile in
                HStack {
                    Text(profile.name)
                    if profile.isDefault {
                        Text(L("hosts.default"))
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                            .foregroundStyle(Color.accentColor)
                    }
                    Spacer()
                }
                .tag(Optional(profile))
            }
            .listStyle(.sidebar)

            Divider()

            HStack(spacing: 6) {
                Button {
                    showNewProfileSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .help(L("hosts.newProfile"))

                Button {
                    let base = vm.selection?.name ?? "hosts"
                    renameDraft = "\(base)-copy"
                    vm.duplicateAsProfile(name: renameDraft)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help(L("hosts.duplicate"))
                .disabled(vm.selection == nil)

                Button {
                    renameDraft = vm.selection?.name ?? ""
                    showRenameSheet = true
                } label: {
                    Image(systemName: "pencil")
                }
                .help(L("hosts.rename"))
                .disabled(vm.selection == nil)

                Button {
                    vm.deleteSelectedProfile()
                } label: {
                    Image(systemName: "trash")
                }
                .help(L("hosts.delete"))
                .disabled(vm.selection == nil)

                Button {
                    vm.setDefault()
                } label: {
                    Image(systemName: "star")
                }
                .help(L("hosts.setDefault"))
                .disabled(vm.selection == nil)
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if vm.selection != nil {
            detailContent
        } else {
            VStack(spacing: 12) {
                Image(systemName: "externaldrive.connected.to.line.below")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text(L("hosts.emptySelect"))
                    .font(.title2.bold())
                Text(L("hosts.emptySelect.hint"))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }

    private var detailContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(vm.selection?.name ?? "")
                        .font(.title2.bold())
                    if vm.systemMatchesCurrentProfile {
                        Text(L("hosts.matchesSystem"))
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.green.opacity(0.2)))
                            .foregroundStyle(Color.green)
                    }
                    Spacer()
                }
                Text(vm.selection?.url.path ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text("\(L("hosts.systemPath"))：\("/etc/hosts")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()

            Divider()

            Picker(L("hosts.mode"), selection: modeBinding) {
                Text(L("hosts.mode.structured")).tag(HostsViewMode.structured)
                Text(L("hosts.mode.raw")).tag(HostsViewMode.raw)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            if vm.viewMode == .structured {
                structuredView
            } else {
                rawView
            }

            if let msg = vm.errorMessage {
                errorBanner(msg)
            }
        }
    }

    private var modeBinding: Binding<HostsViewMode> {
        Binding(
            get: { vm.viewMode },
            set: { vm.switchMode(to: $0) }
        )
    }

    // MARK: - Structured

    private var structuredView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L("hosts.sectionEntries"))
                        .font(.headline)
                    Spacer()
                    Button {
                        vm.addEntry()
                    } label: {
                        Label(L("hosts.addEntry"), systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
                ForEach(indexedEntries(), id: \.value.id) { pair in
                    entryRow(pair.value)
                }
                let unparsedCount = vm.document.lines.reduce(0) { acc, line in
                    if case .unparsed = line { return acc + 1 }
                    return acc
                }
                if unparsedCount > 0 {
                    Text("\(L("hosts.unparsedLines"))：\(unparsedCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
            }
            .padding()
        }
    }

    private func entryRow(_ entry: HostsEntry) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: enabledBinding(id: entry.id))
                .labelsHidden()
                .toggleStyle(.switch)
                .help(L("hosts.entry.enabled"))
            TextField(L("hosts.entry.ip"), text: ipBinding(id: entry.id))
                .frame(width: 140)
            TextField(L("hosts.entry.hostnames"), text: hostnamesBinding(id: entry.id))
                .frame(minWidth: 240)
            TextField(L("hosts.entry.comment"), text: commentBinding(id: entry.id))
                .frame(minWidth: 120)
            Button {
                vm.removeEntry(id: entry.id)
            } label: {
                Image(systemName: "trash").foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
        }
        .padding(8)
        .background(Color.gray.opacity(entry.isEnabled ? 0.06 : 0.14))
        .cornerRadius(6)
        .opacity(entry.isEnabled ? 1.0 : 0.7)
    }

    // MARK: - Raw

    private var rawView: some View {
        ScrollView {
            TextEditor(text: $vm.rawText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 400)
                .padding(8)
        }
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(msg)
                .font(.callout)
                .lineLimit(3)
            Spacer()
            Button {
                vm.errorMessage = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
    }

    // MARK: - Sheet

    private func profileNameSheet(
        title: String,
        initial: String,
        onCommit: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            TextField(L("hosts.profileName"), text: $newProfileName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .onAppear { newProfileName = initial }
            HStack {
                Spacer()
                Button(L("hosts.cancel")) { onCancel() }
                Button(L("hosts.ok")) { onCommit(newProfileName) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }

    // MARK: - Helpers

    private func indexedEntries() -> [(index: Int, value: HostsEntry)] {
        var result: [(Int, HostsEntry)] = []
        for (i, line) in vm.document.lines.enumerated() {
            if case .entry(let e) = line { result.append((i, e)) }
        }
        return result.map { (index: $0.0, value: $0.1) }
    }

    private func currentEntry(id: UUID) -> HostsEntry? {
        for line in vm.document.lines {
            if case .entry(let e) = line, e.id == id { return e }
        }
        return nil
    }

    private func enabledBinding(id: UUID) -> Binding<Bool> {
        Binding(
            get: { currentEntry(id: id)?.isEnabled ?? true },
            set: { vm.updateEntry(id: id, isEnabled: $0) }
        )
    }

    private func ipBinding(id: UUID) -> Binding<String> {
        Binding(
            get: { currentEntry(id: id)?.ip ?? "" },
            set: { vm.updateEntry(id: id, ip: $0) }
        )
    }

    private func hostnamesBinding(id: UUID) -> Binding<String> {
        Binding(
            get: { currentEntry(id: id)?.hostnames.joined(separator: " ") ?? "" },
            set: { newVal in
                let hosts = newVal
                    .split(whereSeparator: { $0 == " " || $0 == "\t" })
                    .map(String.init)
                vm.updateEntry(id: id, hostnames: hosts)
            }
        )
    }

    private func commentBinding(id: UUID) -> Binding<String> {
        Binding(
            get: { currentEntry(id: id)?.comment ?? "" },
            set: { newVal in
                let trimmed = newVal.trimmingCharacters(in: .whitespacesAndNewlines)
                vm.updateEntry(id: id, comment: trimmed.isEmpty ? .some(nil) : .some(trimmed))
            }
        )
    }
}
