import SwiftUI

extension RuntimeKind {
    var systemImage: String {
        NavigationItem.devEnv(self).systemImage
    }
}

public struct RuntimeDetailView: View {
    let kind: RuntimeKind
    @StateObject private var viewModel: RuntimeViewModel
    @State private var selectedTab: Int = 0

    public init(kind: RuntimeKind) {
        self.kind = kind
        _viewModel = StateObject(wrappedValue: RuntimeViewModel(kind: kind))
    }

    private var kindIcon: String { kind.systemImage }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Picker("", selection: $selectedTab) {
                Text("Installed").tag(0)
                Text("Available").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            Group {
                if selectedTab == 0 {
                    InstalledListView(vm: viewModel)
                } else {
                    AvailableListView(vm: viewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let msg = viewModel.errorMessage {
                errorBanner(msg)
            }
        }
        .navigationTitle(kind.displayName)
        .task {
            viewModel.refreshInstalled()
            await viewModel.loadAvailable()
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
                    Text("Active: \(viewModel.activeVersion ?? "None")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if viewModel.activeVersion != nil && !viewModel.isManagedActive {
                        Text("System Default")
                            .font(.caption.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.25)))
                            .foregroundStyle(.orange)
                    }
                }
            }
            Spacer()
            Button("Refresh") {
                Task {
                    await viewModel.loadAvailable()
                    viewModel.refreshInstalled()
                }
            }
        }
        .padding()
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(msg)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(3)
            Spacer()
            Button {
                viewModel.errorMessage = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.orange.opacity(0.4)),
            alignment: .top
        )
    }
}
