import SwiftUI

extension RuntimeKind {
    var systemImage: String {
        NavigationItem.devEnv(self).systemImage
    }
}

public struct RuntimeDetailView: View {
    let kind: RuntimeKind
    @StateObject private var viewModel: RuntimeViewModel
    @EnvironmentObject private var localization: LocalizationManager
    @State private var selectedTab: Int = 0

    public init(kind: RuntimeKind) {
        self.kind = kind
        _viewModel = StateObject(wrappedValue: RuntimeViewModel(kind: kind))
    }

    private var kindIcon: String { kind.systemImage }

    public var body: some View {
        VStack(spacing: 0) {
            header
            ShimsPathBanner()
            Picker("", selection: $selectedTab) {
                Text(L("runtime.installed")).tag(0)
                Text(L("runtime.available")).tag(1)
                Text(L("runtime.usage")).tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            Group {
                if selectedTab == 0 {
                    InstalledListView(vm: viewModel)
                } else if selectedTab == 1 {
                    AvailableListView(vm: viewModel)
                } else {
                    UsageListView(vm: viewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let msg = viewModel.errorMessage {
                StatusBanner(.error, msg, onDismiss: { viewModel.errorMessage = nil })
            }
        }
        .navigationTitle(kind.displayName)
        .task {
            await viewModel.refreshInstalled()
            await viewModel.loadAvailable()
        }
        .onChange(of: selectedTab) { newValue in
            if newValue == 2 && !viewModel.isUsageFresh() && !viewModel.isLoadingUsage {
                Task { await viewModel.refreshUsage(force: false) }
            }
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: kindIcon)
                .font(.largeTitle)
            VStack(alignment: .leading, spacing: 4) {
                Text(kind.displayName)
                    .font(.title.bold())
                HStack(spacing: 6) {
                    Text("\(L("runtime.active")): \(viewModel.activeVersion ?? L("runtime.none"))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if viewModel.activeVersion != nil && !viewModel.isManagedActive {
                        Text(L("runtime.systemDefault"))
                            .font(.caption.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.25)))
                            .foregroundStyle(.orange)
                    }
                }
            }
            Spacer()
            Button(L("runtime.refresh")) {
                Task {
                    await viewModel.loadAvailable()
                    await viewModel.refreshInstalled()
                    await viewModel.refreshUsage(force: true)
                }
            }
        }
        .padding()
    }
}
