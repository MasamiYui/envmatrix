import SwiftUI
import AppKit

/// Non-modal strip shown above the detail pane when a newer release is
/// published. Offers the release page and "skip this version".
struct UpdateAvailableBanner: View {
    @ObservedObject private var checker = UpdateChecker.shared
    @EnvironmentObject private var localization: LocalizationManager

    var body: some View {
        if let release = checker.pendingRelease {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.blue)
                Text(String(format: L("update.banner.title"), release.version, checker.currentVersion))
                    .font(.callout)
                Spacer(minLength: 8)
                Button {
                    checker.skip(release)
                } label: {
                    Text(L("update.banner.skip"))
                }
                .buttonStyle(.borderless)
                Button {
                    NSWorkspace.shared.open(release.url)
                } label: {
                    Label(L("update.banner.open"), systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.blue.opacity(0.10))
            .overlay(alignment: .bottom) {
                Rectangle().frame(height: 1).foregroundStyle(Color.blue.opacity(0.3))
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
