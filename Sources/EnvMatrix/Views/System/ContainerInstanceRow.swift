import SwiftUI

struct ContainerInstanceRow: View {
    let instance: ContainerInstance
    let onStart: () -> Void
    let onStop: () -> Void
    let onRestart: () -> Void
    let onRemove: () -> Void
    let onLogs: () -> Void
    let onInspect: () -> Void

    @State private var showRemoveConfirm: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: stateIcon)
                .foregroundStyle(stateColor)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(displayName)
                        .font(.headline)
                    Text(instance.state.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(stateColor.opacity(0.2)))
                        .foregroundStyle(stateColor)
                }
                Text(instance.image)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !instance.status.isEmpty {
                    Text(instance.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            actions
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .confirmationDialog(
            L("container.instances.confirmRemove"),
            isPresented: $showRemoveConfirm,
            titleVisibility: .visible
        ) {
            Button(L("container.confirm.yes"), role: .destructive, action: onRemove)
            Button(L("container.confirm.no"), role: .cancel) {}
        }
    }

    private var displayName: String {
        instance.names.first ?? String(instance.id.prefix(12))
    }

    private var stateIcon: String {
        switch instance.state {
        case .running: return "play.circle.fill"
        case .paused: return "pause.circle.fill"
        case .exited, .dead: return "stop.circle.fill"
        case .restarting: return "arrow.clockwise.circle.fill"
        case .created: return "circle.dashed"
        case .unknown: return "questionmark.circle"
        }
    }

    private var stateColor: Color {
        switch instance.state {
        case .running: return .green
        case .paused: return .orange
        case .exited: return .gray
        case .dead: return .red
        case .restarting: return .blue
        default: return .secondary
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button(action: onStart) {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.borderless)
            .disabled(instance.state == .running)
            .help(L("container.instances.start"))

            Button(action: onStop) {
                Image(systemName: "stop.fill")
            }
            .buttonStyle(.borderless)
            .disabled(instance.state == .exited || instance.state == .dead)
            .help(L("container.instances.stop"))

            Button(action: onRestart) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(instance.state == .exited || instance.state == .dead)
            .help(L("container.instances.restart"))

            Button(action: onLogs) {
                Image(systemName: "text.alignleft")
            }
            .buttonStyle(.borderless)
            .help(L("container.instances.logs"))

            Button(action: onInspect) {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.borderless)
            .help(L("container.instances.inspect"))

            Button(role: .destructive) {
                showRemoveConfirm = true
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .help(L("container.instances.remove"))
        }
    }
}
