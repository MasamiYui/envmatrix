import SwiftUI

public struct UvGlobalToolsView: View {
    @StateObject private var vm = UvGlobalToolsViewModel()
    @State private var searchText: String = ""

    public init() {}

    public var body: some View {
        Group {
            if !vm.uvAvailable {
                UvMissingView()
            } else {
                mainContent
            }
        }
        .task { await vm.load() }
        .confirmationDialog(
            L("uvRepo.tools.uninstallTitle"),
            isPresented: Binding(
                get: { vm.pendingDelete != nil },
                set: { newValue in if !newValue { vm.cancelDelete() } }
            ),
            titleVisibility: .visible,
            presenting: vm.pendingDelete
        ) { tool in
            Button(L("uvRepo.tools.uninstall"), role: .destructive) {
                Task { await vm.confirmDelete() }
            }
            Button(L("common.cancel"), role: .cancel) {
                vm.cancelDelete()
            }
        } message: { tool in
            Text("\(tool.name)\(tool.version.map { " v\($0)" } ?? "")")
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            if let err = vm.errorMessage {
                errorBanner(err)
            }
            toolbar
            searchBar
            Divider()
            content
        }
    }

    private var toolbar: some View {
        HStack {
            Text(String(format: L("uvRepo.tools.total"), vm.filtered.count))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                Task { await vm.load() }
            } label: {
                Label(L("common.refresh"), systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(vm.isLoading)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(L("uvRepo.tools.search"), text: $searchText)
                .textFieldStyle(.plain)
                .onChange(of: searchText) { newValue in
                    vm.updateSearch(newValue)
                }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    vm.updateSearch("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            VStack(spacing: 12) {
                ProgressView()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.filtered.isEmpty {
            emptyView
        } else {
            toolList
        }
    }

    private var toolList: some View {
        List {
            ForEach(vm.filtered) { tool in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tool.name)
                            .font(.headline)
                        if let version = tool.version {
                            Text("v\(version)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button(role: .destructive) {
                        vm.requestDelete(tool)
                    } label: {
                        Label(L("uvRepo.tools.uninstall"), systemImage: "trash")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, 2)
            }
        }
        .listStyle(.inset)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(L("uvRepo.tools.empty"))
                .font(.title3.bold())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
            Spacer()
        }
        .padding(8)
        .background(Color.red.opacity(0.08))
    }
}
