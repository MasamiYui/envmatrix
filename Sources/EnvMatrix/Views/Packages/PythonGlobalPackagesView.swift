import SwiftUI

public struct PythonGlobalPackagesView: View {
    @StateObject private var vm = PythonGlobalPackagesViewModel()
    @State private var searchText: String = ""

    public init() {}

    public var body: some View {
        Group {
            if !vm.pipAvailable {
                PipMissingView()
            } else {
                mainContent
            }
        }
        .task { await vm.load() }
        .confirmationDialog(
            L("pythonRepo.pkg.confirmDelete"),
            isPresented: Binding(
                get: { vm.pendingDelete != nil },
                set: { newValue in if !newValue { vm.cancelDelete() } }
            ),
            titleVisibility: .visible,
            presenting: vm.pendingDelete
        ) { pkg in
            Button(L("pythonRepo.pkg.uninstall"), role: .destructive) {
                Task { await vm.confirmDelete() }
            }
            Button(L("common.cancel"), role: .cancel) {
                vm.cancelDelete()
            }
        } message: { pkg in
            Text("\(pkg.name) \(pkg.version)")
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
            Text(String(format: L("pythonRepo.pkg.total"), vm.filtered.count))
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
            TextField(L("pythonRepo.pkg.search"), text: $searchText)
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
            packageList
        }
    }

    private var packageList: some View {
        List {
            ForEach(vm.filtered) { pkg in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(pkg.name)
                            .font(.headline)
                        Text(pkg.version)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        vm.requestDelete(pkg)
                    } label: {
                        Label(L("pythonRepo.pkg.uninstall"), systemImage: "trash")
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
            Text(L("pythonRepo.pkg.empty"))
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
