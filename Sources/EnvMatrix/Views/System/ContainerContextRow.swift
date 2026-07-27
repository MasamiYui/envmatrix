import SwiftUI

/// Row showing a single Docker context with action buttons and ping result disclosure.
struct DockerContextRowView: View {
    let ctx: DockerContext
    let pingResult: ContainerPingResult?
    let onUse: () -> Void
    let onPing: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                activeBadge
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(ctx.name)
                            .font(.headline)
                        badges
                    }
                    Text(ctx.endpoint)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                actionButtons
            }
            if let result = pingResult {
                pingDisclosure(result)
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var activeBadge: some View {
        Image(systemName: ctx.isCurrent ? "checkmark.seal.fill" : "circle")
            .foregroundStyle(ctx.isCurrent ? Color.green : Color.secondary)
            .font(.title3)
    }

    @ViewBuilder
    private var badges: some View {
        if ctx.isBuiltIn {
            badge(L("container.badge.builtIn"), color: .gray)
        }
        if ctx.tlsEnabled == true {
            badge(L("container.badge.tls"), color: .blue)
        }
        if ctx.endpoint.hasPrefix("ssh://") {
            badge(L("container.badge.ssh"), color: .purple)
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.2)))
            .foregroundStyle(color)
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button(action: onUse) {
                Image(systemName: "checkmark.circle")
            }
            .buttonStyle(.borderless)
            .help(L("container.action.use"))
            .disabled(ctx.isCurrent)

            Button(action: onPing) {
                Image(systemName: "wave.3.right")
            }
            .buttonStyle(.borderless)
            .help(L("container.action.ping"))

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help(L("container.action.edit"))

            deleteButton
        }
    }

    @ViewBuilder
    private var deleteButton: some View {
        if ctx.isBuiltIn {
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .disabled(true)
            .help(L("container.delete.protectedTooltip"))
        } else {
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .help(L("container.action.delete"))
        }
    }

    private func pingDisclosure(_ result: ContainerPingResult) -> some View {
        HStack(spacing: 8) {
            Image(systemName: result.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .foregroundStyle(result.ok ? Color.green : Color.orange)
            Text(result.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            Text("\(result.latencyMS) ms")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// Row showing a single Podman system connection with action buttons and ping result disclosure.
struct PodmanConnectionRowView: View {
    let conn: PodmanConnection
    let pingResult: ContainerPingResult?
    let onUse: () -> Void
    let onPing: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                activeBadge
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(conn.name)
                            .font(.headline)
                        badges
                    }
                    Text(conn.uri)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                actionButtons
            }
            if let result = pingResult {
                pingDisclosure(result)
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var activeBadge: some View {
        Image(systemName: conn.isDefault ? "checkmark.seal.fill" : "circle")
            .foregroundStyle(conn.isDefault ? Color.green : Color.secondary)
            .font(.title3)
    }

    @ViewBuilder
    private var badges: some View {
        if conn.uri.hasPrefix("ssh://") {
            badge(L("container.badge.ssh"), color: .purple)
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.2)))
            .foregroundStyle(color)
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button(action: onUse) {
                Image(systemName: "checkmark.circle")
            }
            .buttonStyle(.borderless)
            .help(L("container.action.use"))
            .disabled(conn.isDefault)

            Button(action: onPing) {
                Image(systemName: "wave.3.right")
            }
            .buttonStyle(.borderless)
            .help(L("container.action.ping"))

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help(L("container.action.edit"))

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .help(L("container.action.delete"))
        }
    }

    private func pingDisclosure(_ result: ContainerPingResult) -> some View {
        HStack(spacing: 8) {
            Image(systemName: result.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .foregroundStyle(result.ok ? Color.green : Color.orange)
            Text(result.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            Text("\(result.latencyMS) ms")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
