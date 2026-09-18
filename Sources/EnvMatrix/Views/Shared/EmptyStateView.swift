import SwiftUI
import AppKit

/// The one empty / missing-tool placeholder used across the app.
///
/// Beyond icon + title + subtitle it can show a copyable terminal command
/// (for "X is not installed" states) and an optional action button, so an
/// empty screen always tells the user what to do next.
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    var subtitle: String? = nil
    /// A terminal command that resolves the empty state, e.g. `brew install uv`.
    var command: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var compact: Bool = false

    @State private var copied = false

    var body: some View {
        VStack(spacing: compact ? 8 : 12) {
            Image(systemName: systemImage)
                .font(.system(size: compact ? 34 : 48))
                .foregroundStyle(.secondary)
            Text(title)
                .font(compact ? .headline : .title2.bold())
                .multilineTextAlignment(.center)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let command {
                commandChip(command)
                    .padding(.top, 4)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .accessibilityElement(children: .combine)
    }

    private func commandChip(_ command: String) -> some View {
        HStack(spacing: 8) {
            Text(command)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            Button {
                copy(command)
            } label: {
                Label(copied ? L("common.copied") : L("common.copyCommand"),
                      systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
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
