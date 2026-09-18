import SwiftUI

struct PipMissingView: View {
    var body: some View {
        EmptyStateView(
            systemImage: "exclamationmark.triangle",
            title: L("pythonRepo.pipMissing.title"),
            subtitle: L("pythonRepo.pipMissing.subtitle"),
            command: RuntimeKind.python.manualInstallCommand
        )
    }
}
