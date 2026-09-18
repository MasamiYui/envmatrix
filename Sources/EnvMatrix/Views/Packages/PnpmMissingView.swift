import SwiftUI

struct PnpmMissingView: View {
    var body: some View {
        EmptyStateView(
            systemImage: "exclamationmark.triangle",
            title: L("pnpmRepo.missing.title"),
            subtitle: L("pnpmRepo.missing.subtitle"),
            command: "brew install pnpm"
        )
    }
}
