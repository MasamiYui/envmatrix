import SwiftUI

public struct MCPServersView: View {
    @StateObject private var vm = MCPViewModel()
    @EnvironmentObject private var localization: LocalizationManager
    @State private var collapsedTransports: Set<MCPTransport> = []

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
            if vm.servers.isEmpty {
                emptyView
            } else {
                List {
                    ForEach(groupedServers, id: \.transport) { group in
                        Section {
                            if !collapsedTransports.contains(group.transport) {
                                ForEach(group.servers) { server in
                                    row(for: server)
                                }
                            }
                        } header: {
                            groupHeader(transport: group.transport, count: group.servers.count)
                        }
                    }
                }
                .listStyle(.inset)
            }
            if let msg = vm.errorMessage {
                errorBanner(msg)
            }
        }
        .navigationTitle(L("mcp.title"))
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

    private var groupedServers: [(transport: MCPTransport, servers: [MCPServer])] {
        let bucketed = Dictionary(grouping: vm.servers) { server in
            MCPTransport.classify(command: server.command)
        }
        return MCPTransport.allCases.compactMap { t in
            guard let servers = bucketed[t], !servers.isEmpty else { return nil }
            let sorted = servers.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return (t, sorted)
        }
    }

    private func groupHeader(transport: MCPTransport, count: Int) -> some View {
        let isCollapsed = collapsedTransports.contains(transport)
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if isCollapsed {
                    collapsedTransports.remove(transport)
                } else {
                    collapsedTransports.insert(transport)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 10)
                Image(systemName: transport.systemImage)
                    .foregroundStyle(transport.tint)
                Text(L(transport.labelKey))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(count)")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(transport.tint.opacity(0.18), in: Capsule())
                    .foregroundStyle(transport.tint)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

enum MCPTransport: String, CaseIterable, Hashable {
    case npx
    case uvx
    case node
    case python
    case other

    var labelKey: String {
        switch self {
        case .npx: return "mcp.transport.npx"
        case .uvx: return "mcp.transport.uvx"
        case .node: return "mcp.transport.node"
        case .python: return "mcp.transport.python"
        case .other: return "mcp.transport.other"
        }
    }

    var systemImage: String {
        switch self {
        case .npx: return "cube.box.fill"
        case .uvx: return "bolt.fill"
        case .node: return "leaf.fill"
        case .python: return "hexagon.fill"
        case .other: return "terminal.fill"
        }
    }

    var tint: Color {
        switch self {
        case .npx: return .red
        case .uvx: return .purple
        case .node: return .green
        case .python: return .blue
        case .other: return .gray
        }
    }

    static func classify(command: String) -> MCPTransport {
        let raw = command.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = (raw as NSString).lastPathComponent
        switch base {
        case "npx":
            return .npx
        case "uvx":
            return .uvx
        case "node", "nodejs":
            return .node
        case "python", "python3":
            return .python
        default:
            return .other
        }
    }
}
