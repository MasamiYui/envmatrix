import SwiftUI

struct LocalAppLeftoversSheet: View {
    let leftovers: [LocalAppLeftover]
    let onConfirm: (Set<LocalAppLeftover.ID>) -> Void
    let onCancel: () -> Void

    @State private var selection: Set<LocalAppLeftover.ID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("localApps.leftovers.title"))
                .font(.title2.bold())
            Text(L("localApps.leftovers.message"))
                .foregroundStyle(.secondary)

            if leftovers.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Text(L("localApps.leftovers.empty"))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(leftovers) { item in
                    Toggle(isOn: toggleBinding(for: item.id)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.url.lastPathComponent)
                                .font(.body)
                            Text(item.url.path)
                                .foregroundStyle(.secondary)
                                .font(.caption)
                                .lineLimit(1)
                            HStack {
                                Text(kindLabel(item.kind))
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                                Text(sizeFormatted(item.sizeBytes))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }

            HStack {
                Spacer()
                Button(L("localApps.leftovers.cancel")) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button(role: .destructive) {
                    onConfirm(selection)
                } label: {
                    Text(L("localApps.leftovers.trashSelected"))
                }
                .disabled(selection.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 420)
        .onAppear {
            selection = Set(leftovers.map { $0.id })
        }
    }

    private func toggleBinding(for id: LocalAppLeftover.ID) -> Binding<Bool> {
        Binding(
            get: { selection.contains(id) },
            set: { isOn in
                if isOn {
                    selection.insert(id)
                } else {
                    selection.remove(id)
                }
            }
        )
    }

    private func kindLabel(_ kind: LocalAppLeftoverKind) -> String {
        switch kind {
        case .preferences:
            return L("localApps.leftovers.kind.preferences")
        case .caches:
            return L("localApps.leftovers.kind.caches")
        case .appSupport:
            return L("localApps.leftovers.kind.appSupport")
        case .logs:
            return L("localApps.leftovers.kind.logs")
        case .savedState:
            return L("localApps.leftovers.kind.savedState")
        case .containers:
            return L("localApps.leftovers.kind.containers")
        case .groupContainers:
            return L("localApps.leftovers.kind.groupContainers")
        }
    }

    private func sizeFormatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
