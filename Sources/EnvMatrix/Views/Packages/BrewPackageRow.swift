import SwiftUI

struct BrewPackageRow: View {
    let pkg: BrewPackage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: pkg.kind == .cask ? "app.gift.fill" : "shippingbox.fill")
                .foregroundStyle(pkg.kind == .cask ? Color.blue : Color.orange)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(pkg.name)
                        .font(.headline)
                    if pkg.isOutdated {
                        Text("outdated")
                            .font(.caption2.bold())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.orange.opacity(0.25)))
                            .foregroundStyle(.orange)
                    }
                    if pkg.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                    if pkg.isDeprecated {
                        Text("deprecated")
                            .font(.caption2.bold())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.red.opacity(0.2)))
                            .foregroundStyle(.red)
                    }
                    if !pkg.installedOnRequest && pkg.kind == .formula {
                        Text("dep")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .background(Capsule().fill(Color.gray.opacity(0.2)))
                    }
                }
                if let desc = pkg.description {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    if let v = pkg.installedVersion {
                        Text(v)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if let latest = pkg.latestVersion, pkg.isOutdated {
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(latest)
                            .font(.caption.monospacedDigit().bold())
                            .foregroundStyle(.orange)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
