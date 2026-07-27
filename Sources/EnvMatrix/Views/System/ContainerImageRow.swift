import SwiftUI

struct ContainerImageRow: View {
    let image: ContainerImage
    let onTag: () -> Void
    let onRemove: () -> Void
    let onInspect: () -> Void

    @State private var showRemoveConfirm: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "shippingbox")
                .foregroundStyle(.orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(displayName)
                        .font(.headline)
                    if !shortDigest.isEmpty {
                        Text(shortDigest)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 10) {
                    Text(humanBytes(image.sizeBytes))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(relativeCreated)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            actions
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .confirmationDialog(
            L("container.images.confirmRemove"),
            isPresented: $showRemoveConfirm,
            titleVisibility: .visible
        ) {
            Button(L("container.confirm.yes"), role: .destructive, action: onRemove)
            Button(L("container.confirm.no"), role: .cancel) {}
        }
    }

    private var displayName: String {
        let repo = image.repository.isEmpty ? "<none>" : image.repository
        let tag = image.tag.isEmpty ? "<none>" : image.tag
        return "\(repo):\(tag)"
    }

    private var shortDigest: String {
        let raw = image.digest ?? image.id
        let trimmed = raw.hasPrefix("sha256:") ? String(raw.dropFirst("sha256:".count)) : raw
        return String(trimmed.prefix(12))
    }

    private var relativeCreated: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: image.createdAt, relativeTo: Date())
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button(action: onTag) {
                Image(systemName: "pencil.and.outline")
            }
            .buttonStyle(.borderless)
            .help(L("container.images.tag"))

            Button(action: onInspect) {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.borderless)
            .help(L("container.images.inspect"))

            Button(role: .destructive) {
                showRemoveConfirm = true
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .help(L("container.images.remove"))
        }
    }
}

func humanBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useAll]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}
