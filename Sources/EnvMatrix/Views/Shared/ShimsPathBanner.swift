import SwiftUI
import AppKit

/// Warns that "Set Active" has no effect in the terminal until the shims
/// directory is on PATH, and offers a one-click fix plus a copyable line.
///
/// Renders nothing while the check is pending or once PATH is configured.
struct ShimsPathBanner: View {
    @ObservedObject private var status = ShimsPathStatus.shared
    @EnvironmentObject private var localization: LocalizationManager
    @State private var copied = false

    var body: some View {
        Group {
            if let file = status.writtenRcFile {
                successBody(file)
            } else if status.isConfigured == false {
                warningBody
            }
        }
        .onAppear { status.check() }
    }

    private var warningBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("shims.banner.title"))
                        .font(.headline)
                    Text(String(format: L("shims.banner.body"), status.targetRcDisplayName))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Text(status.exportLine)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.subtleFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Button {
                    copy(status.exportLine)
                } label: {
                    Label(copied ? L("shims.banner.copied") : L("shims.banner.copy"),
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer(minLength: 0)

                Button {
                    status.addToShellRc()
                } label: {
                    if status.isWriting {
                        ProgressView().controlSize(.small)
                    } else {
                        Label(String(format: L("shims.banner.addToRc"), status.targetRcDisplayName),
                              systemImage: "square.and.arrow.down")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(status.isWriting)
            }

            if let err = status.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 0.5)
        )
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private func successBody(_ file: ShellRcFile) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: L("shims.banner.done.title"), file.kind.displayName))
                    .font(.headline)
                Text(L("shims.banner.done.body"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([file.url])
            } label: {
                Label(L("shims.banner.reveal"), systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .background(Color.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.green.opacity(0.35), lineWidth: 0.5)
        )
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        copied = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copied = false
        }
    }
}
