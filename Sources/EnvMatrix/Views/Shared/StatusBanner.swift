import SwiftUI

extension Notification.Name {
    /// Posted by `StatusBanner` when the user taps "Diagnostics" on an
    /// error. `RootView` navigates to Settings and `SettingsView` selects
    /// the Diagnostics tab.
    static let envMatrixOpenDiagnostics = Notification.Name("envmatrix.openDiagnostics")
}

/// The one inline status strip used across the app for errors, warnings,
/// successes and informational notices. Replaces the per-view banner
/// helpers so colour, typography and dismiss behaviour stay identical.
///
/// Errors additionally expose a "Diagnostics" shortcut so the user can
/// export a report at the moment something went wrong.
struct StatusBanner: View {
    enum Kind {
        case error
        case warning
        case success
        case info

        var tint: Color {
            switch self {
            case .error: return .red
            case .warning: return .orange
            case .success: return .green
            case .info: return .blue
            }
        }

        var systemImage: String {
            switch self {
            case .error: return "exclamationmark.octagon.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .success: return "checkmark.circle.fill"
            case .info: return "info.circle.fill"
            }
        }
    }

    let kind: Kind
    let message: String
    var onDismiss: (() -> Void)? = nil
    /// Errors show the Diagnostics shortcut by default; pass `false` for
    /// contexts (sheets, settings itself) where it makes no sense.
    var showsDiagnosticsLink: Bool = true

    init(_ kind: Kind, _ message: String, onDismiss: (() -> Void)? = nil, showsDiagnosticsLink: Bool = true) {
        self.kind = kind
        self.message = message
        self.onDismiss = onDismiss
        self.showsDiagnosticsLink = showsDiagnosticsLink
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: kind.systemImage)
                .foregroundStyle(kind.tint)
            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(4)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            if kind == .error && showsDiagnosticsLink {
                Button {
                    NotificationCenter.default.post(name: .envMatrixOpenDiagnostics, object: nil)
                } label: {
                    Label(L("banner.diagnostics"), systemImage: "stethoscope")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help(L("banner.diagnostics.help"))
            }
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help(L("banner.dismiss"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(kind.tint.opacity(0.10))
        .overlay(alignment: .top) {
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(kind.tint.opacity(0.35))
        }
        .accessibilityElement(children: .combine)
    }
}
