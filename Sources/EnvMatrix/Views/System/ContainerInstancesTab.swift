import SwiftUI

private struct InstanceInspectSheetState: Identifiable {
    let id = UUID()
    let title: String
    let content: String
}

struct ContainerInstancesTab: View {
    @ObservedObject var parent: ContainerContextsViewModel

    @State private var inspectSheet: InstanceInspectSheetState?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if parent.dockerAvailable {
                DockerInstancesSection(
                    parent: parent,
                    vm: parent.instancesVMDocker,
                    onInspect: { title, content in
                        inspectSheet = InstanceInspectSheetState(title: title, content: content)
                    }
                )
            } else {
                emptyRow(title: L("container.error.cliMissing"), tip: "brew install docker")
            }

            if parent.podmanAvailable {
                PodmanInstancesSection(
                    parent: parent,
                    vm: parent.instancesVMPodman,
                    onInspect: { title, content in
                        inspectSheet = InstanceInspectSheetState(title: title, content: content)
                    }
                )
            } else {
                emptyRow(title: L("container.error.cliMissing"), tip: "brew install podman")
            }
        }
        .sheet(item: $inspectSheet) { state in
            ContainerInspectSheet(
                title: state.title,
                content: state.content,
                onClose: { inspectSheet = nil }
            )
        }
        .sheet(item: dockerLogsBinding) { state in
            ContainerLogsSheet(
                title: L("container.logs.title"),
                content: state.content,
                onClose: { parent.instancesVMDocker.logsSheet = nil }
            )
        }
        .sheet(item: podmanLogsBinding) { state in
            ContainerLogsSheet(
                title: L("container.logs.title"),
                content: state.content,
                onClose: { parent.instancesVMPodman.logsSheet = nil }
            )
        }
    }

    private var dockerLogsBinding: Binding<ContainerInstancesViewModel.LogsSheetState?> {
        Binding(
            get: { parent.instancesVMDocker.logsSheet },
            set: { parent.instancesVMDocker.logsSheet = $0 }
        )
    }

    private var podmanLogsBinding: Binding<ContainerInstancesViewModel.LogsSheetState?> {
        Binding(
            get: { parent.instancesVMPodman.logsSheet },
            set: { parent.instancesVMPodman.logsSheet = $0 }
        )
    }

    private func emptyRow(title: String, tip: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "shippingbox.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout)
                Text(tip)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct DockerInstancesSection: View {
    @ObservedObject var parent: ContainerContextsViewModel
    @ObservedObject var vm: ContainerInstancesViewModel
    let onInspect: (String, String) -> Void

    var body: some View {
        ContainerInstancesSectionBody(
            engine: .docker,
            iconColor: .blue,
            iconName: "shippingbox",
            vm: vm,
            onInspect: onInspect
        )
    }
}

struct PodmanInstancesSection: View {
    @ObservedObject var parent: ContainerContextsViewModel
    @ObservedObject var vm: ContainerInstancesViewModel
    let onInspect: (String, String) -> Void

    var body: some View {
        ContainerInstancesSectionBody(
            engine: .podman,
            iconColor: .purple,
            iconName: "shippingbox.fill",
            vm: vm,
            onInspect: onInspect
        )
    }
}

private struct ContainerInstancesSectionBody: View {
    let engine: ContainerEngine
    let iconColor: Color
    let iconName: String
    @ObservedObject var vm: ContainerInstancesViewModel
    let onInspect: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            toolbar
            content
            if let error = vm.errorMessage {
                errorBanner(error)
            }
        }
        .task { await autoRefresh() }
        .onAppear { Task { await autoRefresh() } }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
            Text(engine.displayName)
                .font(.headline)
            Text("\(vm.filteredInstances.count)")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(iconColor.opacity(0.18), in: Capsule())
                .foregroundStyle(iconColor)
            if vm.isBusy {
                ProgressView().controlSize(.small)
            }
            Spacer()
            Button(action: { Task { await vm.refresh() } }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help(L("container.action.refresh"))
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            TextField(L("container.instances.searchPlaceholder"), text: $vm.keyword)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)

            Picker(L("container.instances.filterLabel"), selection: $vm.filter) {
                Text(L("container.instances.filter.all")).tag(ContainerInstanceFilter.all)
                Text(L("container.instances.filter.running")).tag(ContainerInstanceFilter.running)
                Text(L("container.instances.filter.exited")).tag(ContainerInstanceFilter.exited)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 260)

            Spacer()
        }
    }

    @ViewBuilder
    private var content: some View {
        let list = vm.filteredInstances
        if list.isEmpty {
            emptyRow(title: L("container.instances.empty"))
        } else {
            VStack(spacing: 6) {
                ForEach(list) { instance in
                    ContainerInstanceRow(
                        instance: instance,
                        onStart: { Task { await vm.start(id: instance.id) } },
                        onStop: { Task { await vm.stop(id: instance.id) } },
                        onRestart: { Task { await vm.restart(id: instance.id) } },
                        onRemove: { Task { await vm.remove(id: instance.id) } },
                        onLogs: { Task { await vm.viewLogs(id: instance.id) } },
                        onInspect: {
                            Task {
                                if let text = await vm.inspect(id: instance.id) {
                                    let name = instance.names.first ?? instance.id
                                    onInspect(name, text)
                                }
                            }
                        }
                    )
                }
            }
        }
    }

    private func emptyRow(title: String) -> some View {
        HStack {
            Image(systemName: "tray")
                .foregroundStyle(.secondary)
            Text(title).font(.callout).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(msg)
                .font(.callout)
                .lineLimit(3)
            Spacer()
            Button(action: { vm.errorMessage = nil }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func autoRefresh() async {
        if vm.isStale || vm.instances.isEmpty {
            await vm.refresh()
        }
    }
}
