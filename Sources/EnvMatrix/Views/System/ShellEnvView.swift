import SwiftUI

public struct ShellEnvView: View {
    @StateObject private var vm = ShellEnvViewModel()
    @EnvironmentObject private var localization: LocalizationManager
    @State private var newSegmentDrafts: [UUID: String] = [:]

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(minWidth: 220, maxWidth: 280)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(L("shellEnv.title"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    vm.save()
                } label: {
                    Label(L("shellEnv.save"), systemImage: "square.and.arrow.down")
                }
                .disabled(vm.selection == nil)
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    vm.refresh()
                } label: {
                    Label(L("shellEnv.refresh"), systemImage: "arrow.clockwise")
                }
            }
        }
        .task { vm.refresh() }
        .onChange(of: vm.selection) { newValue in
            if let s = newValue { vm.select(s) }
        }
    }

    private var sidebar: some View {
        List(vm.files, selection: $vm.selection) { file in
            HStack {
                Text(file.kind.displayName)
                Spacer()
                if file.isCurrentShell {
                    Text(L("shellEnv.currentShell"))
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .tag(Optional(file))
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var detail: some View {
        if vm.selection != nil {
            detailContent
        } else {
            VStack(spacing: 12) {
                Image(systemName: "terminal")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text(L("shellEnv.emptySelect"))
                    .font(.title2.bold())
                Text(L("shellEnv.emptySelect.hint"))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }

    private var detailContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(vm.selection?.kind.displayName ?? "")
                    .font(.title2.bold())
                Text(vm.selection?.url.path ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .padding()

            Divider()

            Picker(L("shellEnv.mode"), selection: modeBinding) {
                Text(L("shellEnv.mode.structured")).tag(ShellEnvViewMode.structured)
                Text(L("shellEnv.mode.raw")).tag(ShellEnvViewMode.raw)
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

    private var modeBinding: Binding<ShellEnvViewMode> {
        Binding(
            get: { vm.viewMode },
            set: { newMode in vm.switchMode(to: newMode) }
        )
    }

    private var structuredView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                variablesSection
                Divider()
                pathSection
                let unparsedCount = vm.document.entries.reduce(0) { acc, entry in
                    if case .unparsed = entry { return acc + 1 }
                    return acc
                }
                if unparsedCount > 0 {
                    Text("\(L("shellEnv.unparsedLines"))：\(unparsedCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
            }
            .padding()
        }
    }

    private var variablesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("shellEnv.sectionVariables"))
                    .font(.headline)
                Spacer()
                Button {
                    vm.addVariable()
                } label: {
                    Label(L("shellEnv.addVariable"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            ForEach(indexedVariables(), id: \.value.id) { pair in
                variableRow(index: pair.index, variable: pair.value)
            }
        }
    }

    private func variableRow(index: Int, variable v: ShellVariable) -> some View {
        HStack(spacing: 8) {
            Toggle(L("shellEnv.export"), isOn: exportedBinding(id: v.id))
                .toggleStyle(.checkbox)
            TextField(L("shellEnv.key"), text: keyBinding(id: v.id))
                .frame(width: 180)
            TextField(L("shellEnv.value"), text: valueBinding(id: v.id))
                .frame(minWidth: 200)
            Picker(L("shellEnv.quoting"), selection: quotingBinding(id: v.id)) {
                Text(L("shellEnv.quoting.double")).tag(ShellQuoting.double)
                Text(L("shellEnv.quoting.single")).tag(ShellQuoting.single)
                Text(L("shellEnv.quoting.none")).tag(ShellQuoting.none)
            }
            .pickerStyle(.menu)
            .frame(width: 110)
            Button(action: { vm.removeVariable(id: v.id) }) {
                Image(systemName: "trash").foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
        }
        .padding(8)
        .background(Color.gray.opacity(0.06))
        .cornerRadius(6)
    }

    private var pathSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("shellEnv.sectionPath"))
                    .font(.headline)
                Spacer()
                Button {
                    vm.addPathAppendEntry()
                } label: {
                    Label(L("shellEnv.addPathGroup"), systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
            ForEach(indexedPaths(), id: \.value.id) { pair in
                pathCard(entry: pair.value)
            }
        }
    }

    private func pathCard(entry: ShellPathAppend) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.style == .doubleQuoted ? "\"$PATH:...\"" : "$PATH:...")
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    vm.removePathAppendEntry(id: entry.id)
                    newSegmentDrafts[entry.id] = nil
                } label: {
                    Label(L("shellEnv.removePathGroup"), systemImage: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
            }
            ForEach(Array(entry.segments.enumerated()), id: \.offset) { idx, seg in
                HStack(spacing: 8) {
                    TextField("", text: segmentBinding(entryID: entry.id, index: idx, initial: seg))
                    Button {
                        vm.removePathAppendSegment(pathEntryID: entry.id, at: idx)
                    } label: {
                        Label(L("shellEnv.removeSegment"), systemImage: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                }
            }
            HStack(spacing: 8) {
                TextField(L("shellEnv.segment.placeholder"), text: draftBinding(entryID: entry.id))
                    .onSubmit { commitDraft(entryID: entry.id) }
                Button {
                    commitDraft(entryID: entry.id)
                } label: {
                    Label(L("shellEnv.addSegment"), systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(10)
        .background(Color.gray.opacity(0.08))
        .cornerRadius(8)
    }

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

    private func indexedVariables() -> [(index: Int, value: ShellVariable)] {
        var result: [(Int, ShellVariable)] = []
        for (i, e) in vm.document.entries.enumerated() {
            if case .variable(let v) = e { result.append((i, v)) }
        }
        return result.map { (index: $0.0, value: $0.1) }
    }

    private func indexedPaths() -> [(index: Int, value: ShellPathAppend)] {
        var result: [(Int, ShellPathAppend)] = []
        for (i, e) in vm.document.entries.enumerated() {
            if case .pathAppend(let p) = e { result.append((i, p)) }
        }
        return result.map { (index: $0.0, value: $0.1) }
    }

    private func currentVariable(id: UUID) -> ShellVariable? {
        for e in vm.document.entries {
            if case .variable(let v) = e, v.id == id { return v }
        }
        return nil
    }

    private func keyBinding(id: UUID) -> Binding<String> {
        Binding(
            get: { currentVariable(id: id)?.key ?? "" },
            set: { newVal in vm.updateVariable(id: id, key: newVal, value: nil, quoting: nil, isExported: nil) }
        )
    }

    private func valueBinding(id: UUID) -> Binding<String> {
        Binding(
            get: { currentVariable(id: id)?.value ?? "" },
            set: { newVal in vm.updateVariable(id: id, key: nil, value: newVal, quoting: nil, isExported: nil) }
        )
    }

    private func quotingBinding(id: UUID) -> Binding<ShellQuoting> {
        Binding(
            get: { currentVariable(id: id)?.quoting ?? .double },
            set: { newVal in vm.updateVariable(id: id, key: nil, value: nil, quoting: newVal, isExported: nil) }
        )
    }

    private func exportedBinding(id: UUID) -> Binding<Bool> {
        Binding(
            get: { currentVariable(id: id)?.isExported ?? false },
            set: { newVal in vm.updateVariable(id: id, key: nil, value: nil, quoting: nil, isExported: newVal) }
        )
    }

    private func segmentBinding(entryID: UUID, index: Int, initial: String) -> Binding<String> {
        Binding(
            get: {
                for e in vm.document.entries {
                    if case .pathAppend(let p) = e, p.id == entryID, index < p.segments.count {
                        return p.segments[index]
                    }
                }
                return initial
            },
            set: { newVal in
                for entryIndex in vm.document.entries.indices {
                    if case .pathAppend(let existing) = vm.document.entries[entryIndex], existing.id == entryID {
                        var segments = existing.segments
                        guard index >= 0, index < segments.count else { return }
                        segments[index] = newVal
                        let updated = ShellPathAppend(id: existing.id, segments: segments, style: existing.style)
                        vm.document.entries[entryIndex] = .pathAppend(updated)
                        return
                    }
                }
            }
        )
    }

    private func draftBinding(entryID: UUID) -> Binding<String> {
        Binding(
            get: { newSegmentDrafts[entryID] ?? "" },
            set: { newSegmentDrafts[entryID] = $0 }
        )
    }

    private func commitDraft(entryID: UUID) {
        let value = newSegmentDrafts[entryID] ?? ""
        vm.addPathAppendSegment(pathEntryID: entryID, segment: value)
        newSegmentDrafts[entryID] = ""
    }
}
