import SwiftUI

public struct CLIConfigView: View {
    @StateObject private var vm = CLIConfigViewModel()
    @EnvironmentObject private var localization: LocalizationManager

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(minWidth: 200, maxWidth: 260)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(L("cli.title"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    vm.save()
                } label: {
                    Label(L("cli.save"), systemImage: "square.and.arrow.down")
                }
                .disabled(vm.selection == nil)
            }
        }
        .task { vm.refresh() }
        .onChange(of: vm.selection) { newValue in
            if let s = newValue { vm.select(s) }
        }
    }

    private var sidebar: some View {
        List(vm.configs, selection: $vm.selection) { config in
            Text(config.displayName)
                .tag(Optional(config))
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var detail: some View {
        if let selection = vm.selection {
            form(for: selection)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "terminal")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text(L("cli.selectPrompt"))
                    .font(.title2.bold())
                Text(L("cli.selectHint"))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }

    private func form(for selection: CLIConfig) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selection.displayName)
                    .font(.title2.bold())
                Text(selection.filePath.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .padding()

            Divider()

            Form {
                TextField(L("cli.model"), text: $vm.model)
                TextField(L("cli.apiBaseURL"), text: $vm.apiBaseURL)
                SecureField(L("cli.apiKey"), text: $vm.apiKey)
            }
            .formStyle(.grouped)

            if let msg = vm.errorMessage {
                errorBanner(msg)
            }
            Spacer()
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
}
