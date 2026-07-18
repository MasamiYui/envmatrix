import SwiftUI

struct MCPServerEditorSheet: View {
    @ObservedObject var vm: MCPViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var command: String = ""
    @State private var argsText: String = ""
    @State private var envEntries: [EnvEntry] = []

    struct EnvEntry: Identifiable {
        let id = UUID()
        var key: String
        var value: String
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Form {
                Section(L("mcp.editor.basics")) {
                    TextField(L("mcp.editor.name"), text: $name)
                    TextField(L("mcp.editor.command"), text: $command)
                }
                Section(L("mcp.editor.arguments")) {
                    TextField(L("mcp.editor.argsPlaceholder"), text: $argsText)
                        .help(L("mcp.editor.argsHelp"))
                }
                Section(L("mcp.editor.envVars")) {
                    ForEach($envEntries) { $entry in
                        HStack {
                            TextField(L("mcp.editor.envKey"), text: $entry.key)
                            TextField(L("mcp.editor.envValue"), text: $entry.value)
                            Button {
                                removeEnv(id: entry.id)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    Button {
                        envEntries.append(EnvEntry(key: "", value: ""))
                    } label: {
                        Label(L("mcp.editor.addVariable"), systemImage: "plus")
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            footer
        }
        .frame(minWidth: 480, minHeight: 420)
        .onAppear(perform: load)
    }

    private var header: some View {
        HStack {
            Text(vm.editing != nil && vm.servers.contains(where: { $0.id == vm.editing?.id })
                 ? L("mcp.editor.editTitle")
                 : L("mcp.editor.addTitle"))
                .font(.title2.bold())
            Spacer()
        }
        .padding()
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button(L("mcp.editor.cancel"), role: .cancel) {
                vm.isPresentingEditor = false
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            Button(L("mcp.editor.save")) {
                saveServer()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                      || command.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding()
    }

    private func load() {
        guard let editing = vm.editing else { return }
        name = editing.name
        command = editing.command
        argsText = editing.args.joined(separator: ",")
        envEntries = editing.env
            .sorted(by: { $0.key < $1.key })
            .map { EnvEntry(key: $0.key, value: $0.value) }
    }

    private func removeEnv(id: UUID) {
        envEntries.removeAll { $0.id == id }
    }

    private func saveServer() {
        guard let editing = vm.editing else { return }
        let args = argsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var env: [String: String] = [:]
        for entry in envEntries {
            let key = entry.key.trimmingCharacters(in: .whitespaces)
            if key.isEmpty { continue }
            env[key] = entry.value
        }
        let updated = MCPServer(
            id: editing.id,
            name: name.trimmingCharacters(in: .whitespaces),
            command: command.trimmingCharacters(in: .whitespaces),
            args: args,
            env: env
        )
        vm.save(updated)
        dismiss()
    }
}
