import SwiftUI

struct PackageRepoMissingView: View {
    let title: String
    let subtitle: String
    var command: String? = nil
    var body: some View {
        EmptyStateView(
            systemImage: "exclamationmark.triangle",
            title: title,
            subtitle: subtitle,
            command: command
        )
    }
}

struct PackageCacheCard<Stats>: View where Stats: Any {
    let path: String
    let size: Int64?
    let isCleaning: Bool
    let onClean: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "folder").foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("nodeRepo.cache.path"))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(path)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                Spacer()
            }
            Divider()
            HStack(spacing: 8) {
                Image(systemName: "internaldrive").foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("nodeRepo.cache.size"))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(formatted(size))
                        .font(.title3.bold())
                }
                Spacer()
                Button(role: .destructive) {
                    onClean()
                } label: {
                    Label(L("nodeRepo.cache.clean"), systemImage: "trash")
                }
                .disabled(isCleaning || size == nil)
            }
            if isCleaning {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text(L("nodeRepo.cache.clean"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func formatted(_ size: Int64?) -> String {
        guard let s = size else { return "-" }
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: s)
    }
}
