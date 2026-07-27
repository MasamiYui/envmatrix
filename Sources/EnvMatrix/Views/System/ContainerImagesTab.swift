import SwiftUI

private struct InspectSheetState: Identifiable {
    let id = UUID()
    let engine: ContainerEngine
    let title: String
    let content: String
}

private struct PullSheetState: Identifiable {
    let id = UUID()
    let engine: ContainerEngine
}

struct ContainerImagesTab: View {
    @ObservedObject var parent: ContainerContextsViewModel

    @State private var pullSheet: PullSheetState?
    @State private var inspectSheet: InspectSheetState?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if parent.dockerAvailable {
                DockerImagesSection(
                    parent: parent,
                    vm: parent.imagesVMDocker,
                    onPull: { pullSheet = PullSheetState(engine: .docker) },
                    onInspect: { title, content in
                        inspectSheet = InspectSheetState(engine: .docker, title: title, content: content)
                    }
                )
            } else {
                emptyRow(title: L("container.error.cliMissing"), tip: "brew install docker")
            }

            if parent.podmanAvailable {
                PodmanImagesSection(
                    parent: parent,
                    vm: parent.imagesVMPodman,
                    onPull: { pullSheet = PullSheetState(engine: .podman) },
                    onInspect: { title, content in
                        inspectSheet = InspectSheetState(engine: .podman, title: title, content: content)
                    }
                )
            } else {
                emptyRow(title: L("container.error.cliMissing"), tip: "brew install podman")
            }
        }
        .sheet(item: $pullSheet) { state in
            ContainerImagePullSheet(
                vm: state.engine == .docker ? parent.imagesVMDocker : parent.imagesVMPodman,
                onClose: { pullSheet = nil }
            )
        }
        .sheet(item: $inspectSheet) { state in
            ContainerInspectSheet(
                title: state.title,
                content: state.content,
                onClose: { inspectSheet = nil }
            )
        }
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

struct DockerImagesSection: View {
    @ObservedObject var parent: ContainerContextsViewModel
    @ObservedObject var vm: ContainerImagesViewModel
    let onPull: () -> Void
    let onInspect: (String, String) -> Void

    var body: some View {
        ContainerImagesSectionBody(
            engine: .docker,
            iconColor: .blue,
            iconName: "shippingbox",
            vm: vm,
            onPull: onPull,
            onInspect: onInspect
        )
    }
}

struct PodmanImagesSection: View {
    @ObservedObject var parent: ContainerContextsViewModel
    @ObservedObject var vm: ContainerImagesViewModel
    let onPull: () -> Void
    let onInspect: (String, String) -> Void

    var body: some View {
        ContainerImagesSectionBody(
            engine: .podman,
            iconColor: .purple,
            iconName: "shippingbox.fill",
            vm: vm,
            onPull: onPull,
            onInspect: onInspect
        )
    }
}

private struct ContainerImagesSectionBody: View {
    let engine: ContainerEngine
    let iconColor: Color
    let iconName: String
    @ObservedObject var vm: ContainerImagesViewModel
    let onPull: () -> Void
    let onInspect: (String, String) -> Void

    @State private var includeUnused: Bool = false

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
            Text("\(vm.filteredSortedImages.count)")
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
            TextField(L("container.images.searchPlaceholder"), text: $vm.keyword)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)

            Picker(L("container.images.sortLabel"), selection: $vm.sort) {
                Text(L("container.images.sort.name")).tag(ContainerImageSort.name)
                Text(L("container.images.sort.size")).tag(ContainerImageSort.size)
                Text(L("container.images.sort.createdAt")).tag(ContainerImageSort.createdAt)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 140)

            Spacer()

            Toggle(L("container.images.pruneIncludeUnused"), isOn: $includeUnused)
                .toggleStyle(.checkbox)

            Button(action: { Task { _ = await vm.prune(includeUnused: includeUnused) } }) {
                Label(L("container.images.prune"), systemImage: "wind")
            }
            .disabled(vm.isBusy)

            Button(action: onPull) {
                Label(L("container.images.pull"), systemImage: "arrow.down.circle")
            }
            .disabled(vm.isBusy)
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var content: some View {
        let list = vm.filteredSortedImages
        if list.isEmpty {
            emptyRow(title: L("container.images.empty"))
        } else {
            VStack(spacing: 6) {
                ForEach(list) { image in
                    ContainerImageRow(
                        image: image,
                        onTag: { Task { await vm.tag(source: image.id, dest: image.repository + ":" + image.tag) } },
                        onRemove: { Task { await vm.remove(id: image.id) } },
                        onInspect: {
                            Task {
                                if let text = await vm.inspect(id: image.id) {
                                    onInspect(image.repository + ":" + image.tag, text)
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
        if vm.isStale || vm.images.isEmpty {
            await vm.refresh()
        }
    }
}
