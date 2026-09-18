import SwiftUI

struct UvMissingView: View {
    var body: some View {
        EmptyStateView(
            systemImage: "exclamationmark.triangle",
            title: L("uvRepo.missing.title"),
            subtitle: L("uvRepo.missing.subtitle"),
            command: "brew install uv"
        )
    }
}
