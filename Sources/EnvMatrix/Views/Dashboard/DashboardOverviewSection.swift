import SwiftUI

/// Container engines summary. Skills / MCP / storage counts moved into
/// the page-header chips (which navigate on click), so this section no
/// longer repeats them.
struct DashboardOverviewSection: View {
    @ObservedObject var viewModel: DashboardViewModel

    private let overviewColumns: [GridItem] = [
        GridItem(.adaptive(minimum: 240, maximum: 360), spacing: 16, alignment: .top)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DashboardOverviewSectionHeader(
                icon: "shippingbox.and.arrow.backward.fill",
                title: L("dashboard.section.containers")
            )
            LazyVGrid(columns: overviewColumns, spacing: 16) {
                ContainerOverviewCard()
            }
        }
    }

    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct DashboardOverviewSectionHeader: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
        }
    }
}
