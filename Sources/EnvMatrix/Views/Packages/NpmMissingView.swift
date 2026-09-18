import SwiftUI

struct NpmMissingView: View {
    var body: some View {
        EmptyStateView(
            systemImage: "exclamationmark.triangle",
            title: L("nodeRepo.npmMissing.title"),
            subtitle: L("nodeRepo.npmMissing.subtitle"),
            command: RuntimeKind.node.manualInstallCommand
        )
    }
}
