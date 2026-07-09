import SwiftUI

public struct MCPServersView: View {
    @StateObject private var vm = MCPViewModel()

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
        .navigationTitle("MCP Servers")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    vm.startAdd()
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .task { vm.refresh() }
        .sheet(isPresented: $vm.isPresentingEditor) {
            MCPServerEditorSheet(vm: vm)
        }
    }

    private var header: some View {
        HStack {
            Text("MCP Servers")
                .font(.title.bold())
            Spacer()
            Button("Refresh") { vm.refresh() }
        }
        .padding()
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "bolt.horizontal")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No MCP Servers")
                .font(.title2.bold())
            Text("Click Add to configure a new server.")
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
                Text("\(server.args.count) arg\(server.args.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Edit") { vm.startEdit(server) }
            Divider()
            Button("Delete", role: .destructive) { vm.delete(server) }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Delete", role: .destructive) { vm.delete(server) }
            Button("Edit") { vm.startEdit(server) }
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
