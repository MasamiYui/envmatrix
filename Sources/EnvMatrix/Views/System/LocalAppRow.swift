import AppKit
import SwiftUI

struct LocalAppRow: View {
    let app: LocalApp
    let isProtected: Bool
    let onOpen: () -> Void
    let onReveal: () -> Void
    let onUninstall: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            iconView
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.displayName)
                    .font(.headline)
                HStack(spacing: 8) {
                    Text(app.version)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text(app.bundleId)
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                        .lineLimit(1)
                }
            }

            Spacer()

            sourceBadge
                .fixedSize()

            Text(sizeFormatted(app.sizeBytes))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)

            actionButtons
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var iconView: some View {
        if app.iconPath != nil {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundlePath.path))
                .resizable()
                .frame(width: 32, height: 32)
        } else {
            Image(systemName: "app.fill")
                .resizable()
                .frame(width: 28, height: 28)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var sourceBadge: some View {
        switch app.source {
        case .appStore:
            badgeText(L("localApps.source.appStore"), color: .blue)
        case .brewCask(let token):
            badgeText("\(L("localApps.source.brew")) · \(token)", color: .orange)
        case .other:
            badgeText(L("localApps.source.other"), color: .gray)
        }
    }

    private func badgeText(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.2)))
            .foregroundStyle(color)
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button(action: onOpen) {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
            .help(L("localApps.action.open"))

            Button(action: onReveal) {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help(L("localApps.action.reveal"))

            uninstallButton
        }
    }

    @ViewBuilder
    private var uninstallButton: some View {
        if isProtected {
            Button(action: onUninstall) {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .disabled(true)
            .help(L("localApps.protected.tooltip"))
        } else {
            Button(role: .destructive, action: onUninstall) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .help(L("localApps.action.uninstall"))
        }
    }

    private func sizeFormatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
