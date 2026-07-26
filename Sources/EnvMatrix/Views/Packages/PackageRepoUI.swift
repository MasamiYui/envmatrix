import SwiftUI

struct PackageRepoBanner: View {
    let text: String
    let color: Color
    let icon: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).font(.caption).foregroundStyle(color)
            Spacer()
        }
        .padding(8)
        .background(color.opacity(0.08))
    }
}

struct PackageRepoMissingView: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(title).font(.title2.bold())
            Text(subtitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct PackageRepoHeader: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon).font(.title).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title2.bold())
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
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
