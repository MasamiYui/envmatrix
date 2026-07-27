import SwiftUI

/// Container Contexts screen listing Docker CLI contexts and Podman system connections.
public struct ContainerContextsView: View {
    @StateObject var viewModel = ContainerContextsViewModel()
    @EnvironmentObject private var localization: LocalizationManager
    @State private var dockerEditor: DockerEditorState?
    @State private var podmanEditor: PodmanEditorState?

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                tabPicker
                switch viewModel.selectedTab {
                case .contexts:
                    dockerSection
                    if let msg = viewModel.dockerError {
                        errorBanner(msg) { viewModel.dockerError = nil }
                    }
                    podmanSection
                    if let msg = viewModel.podmanError {
                        errorBanner(msg) { viewModel.podmanError = nil }
                    }
                    if let notice = viewModel.podmanNotice {
                        errorBanner(notice) { viewModel.podmanNotice = nil }
                    }
                case .images:
                    ContainerImagesTab(parent: viewModel)
                case .containers:
                    ContainerInstancesTab(parent: viewModel)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .navigationTitle(L("container.title"))
        .task { await viewModel.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ContainerContextsSetTab"))) { note in
            guard let userInfo = note.userInfo,
                  let raw = userInfo["tab"] as? String,
                  let tab = ContainerContextsTab(rawValue: raw) else { return }
            viewModel.selectedTab = tab
        }
        .sheet(item: $dockerEditor) { state in
            DockerEditorSheet(
                viewModel: viewModel,
                state: state,
                onDismiss: { dockerEditor = nil }
            )
            .environmentObject(localization)
        }
        .sheet(item: $podmanEditor) { state in
            PodmanEditorSheet(
                viewModel: viewModel,
                state: state,
                onDismiss: { podmanEditor = nil }
            )
            .environmentObject(localization)
        }
    }

    private var tabPicker: some View {
        Picker("", selection: $viewModel.selectedTab) {
            Text(L("container.tab.contexts")).tag(ContainerContextsTab.contexts)
            Text(L("container.tab.images")).tag(ContainerContextsTab.images)
            Text(L("container.tab.containers")).tag(ContainerContextsTab.containers)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("container.title"))
                .font(.title.bold())
            Text(L("container.subtitle"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var dockerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                icon: "shippingbox",
                iconColor: .blue,
                title: L("container.docker.section"),
                count: viewModel.dockerContexts.count,
                isCollapsed: viewModel.dockerCollapsed,
                isBusy: viewModel.isDockerBusy,
                onToggle: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewModel.dockerCollapsed.toggle()
                    }
                },
                onAdd: { dockerEditor = .create },
                onRefresh: { Task { await viewModel.refresh() } }
            )
            if !viewModel.dockerCollapsed {
                dockerContent
            }
        }
    }

    @ViewBuilder
    private var dockerContent: some View {
        if !viewModel.dockerAvailable {
            emptyRow(
                icon: "shippingbox.circle",
                title: L("container.error.cliMissing"),
                tip: "brew install docker"
            )
        } else if viewModel.dockerContexts.isEmpty {
            emptyRow(
                icon: "shippingbox.circle",
                title: L("container.docker.empty"),
                tip: nil
            )
        } else {
            VStack(spacing: 8) {
                ForEach(viewModel.dockerContexts) { ctx in
                    DockerContextRowView(
                        ctx: ctx,
                        pingResult: viewModel.pingResults["docker/\(ctx.name)"],
                        onUse: { Task { await viewModel.useDocker(ctx.name) } },
                        onPing: { Task { await viewModel.ping(engine: .docker, name: ctx.name) } },
                        onEdit: { dockerEditor = .edit(ctx) },
                        onDelete: { Task { await viewModel.removeDockerContext(ctx.name) } }
                    )
                }
            }
        }
    }

    private var podmanSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                icon: "shippingbox.fill",
                iconColor: .purple,
                title: L("container.podman.section"),
                count: viewModel.podmanConnections.count,
                isCollapsed: viewModel.podmanCollapsed,
                isBusy: viewModel.isPodmanBusy,
                onToggle: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewModel.podmanCollapsed.toggle()
                    }
                },
                onAdd: { podmanEditor = .create },
                onRefresh: { Task { await viewModel.refresh() } }
            )
            if !viewModel.podmanCollapsed {
                podmanContent
            }
        }
    }

    @ViewBuilder
    private var podmanContent: some View {
        if !viewModel.podmanAvailable {
            emptyRow(
                icon: "shippingbox.circle",
                title: L("container.error.cliMissing"),
                tip: "brew install podman"
            )
        } else if viewModel.podmanConnections.isEmpty {
            emptyRow(
                icon: "shippingbox.circle",
                title: L("container.podman.empty"),
                tip: nil
            )
        } else {
            VStack(spacing: 8) {
                ForEach(viewModel.podmanConnections) { conn in
                    PodmanConnectionRowView(
                        conn: conn,
                        pingResult: viewModel.pingResults["podman/\(conn.name)"],
                        onUse: { Task { await viewModel.setPodmanDefault(conn.name) } },
                        onPing: { Task { await viewModel.ping(engine: .podman, name: conn.name) } },
                        onEdit: { podmanEditor = .edit(conn) },
                        onDelete: { Task { await viewModel.removePodmanConnection(conn.name) } }
                    )
                }
            }
        }
    }

    private func sectionHeader(
        icon: String,
        iconColor: Color,
        title: String,
        count: Int,
        isCollapsed: Bool,
        isBusy: Bool,
        onToggle: @escaping () -> Void,
        onAdd: @escaping () -> Void,
        onRefresh: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
            }
            .buttonStyle(.plain)

            Image(systemName: icon)
                .foregroundStyle(iconColor)
            Text(title)
                .font(.headline)
            Text("\(count)")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(iconColor.opacity(0.18), in: Capsule())
                .foregroundStyle(iconColor)

            if isBusy {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer()

            Button(action: onAdd) {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help(L("container.action.add"))

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help(L("container.action.refresh"))
        }
    }

    private func emptyRow(icon: String, title: String, tip: String?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                if let tip = tip {
                    Text(tip)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            Spacer()
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func errorBanner(_ msg: String, onDismiss: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(msg)
                .font(.callout)
                .lineLimit(3)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
