import SwiftUI

public struct MCPServersView: View {
    @StateObject private var vm = MCPViewModel()
    @EnvironmentObject private var localization: LocalizationManager

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
            if vm.servers.isEmpty {
                emptyView
            } else {
                List {
                    ForEach(vm.servers) { server in
                        row(for: server)
                    }
                }
                .listStyle(.inset)
            }
            if let msg = vm.errorMessage {
                errorBanner(msg)
            }
        }
        .navigationTitle(L("mcp.title"))
        .id(localization.language)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    vm.startAdd()
                } label: {
                    Label(L("mcp.add"), systemImage: "plus")
                }
            }
        }
        .task { vm.refresh() }
        .sheet(isPresented: $vm.isPresentingEditor) {
            MCPServerEditorSheet(vm: vm)
                .environmentObject(localization)
        }
    }

    private var header: some View {
        HStack {
            Text(L("mcp.title"))
                .font(.title.bold())
            Spacer()
            Button(L("mcp.refresh")) { vm.refresh() }
        }
        .padding()
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "bolt.horizontal")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(L("mcp.empty.title"))
                .font(.title2.bold())
            Text(L("mcp.empty.subtitle"))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    @ViewBuilder
    private func row(for server: MCPServer) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(server.name).font(.headline)
                Text(server.command)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(String(format: L(server.args.count == 1 ? "mcp.argCount.one" : "mcp.argCount.many"), server.args.count))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button(L("mcp.edit")) { vm.startEdit(server) }
            Divider()
            Button(L("mcp.delete"), role: .destructive) { vm.delete(server) }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(L("mcp.delete"), role: .destructive) { vm.delete(server) }
            Button(L("mcp.edit")) { vm.startEdit(server) }
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
