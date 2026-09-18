import SwiftUI

extension Notification.Name {
    /// Posted by the View › Refresh menu item (⌘R). The visible page's
    /// `PageHeader` forwards it to its `onRefresh` closure.
    static let envMatrixRefreshRequested = Notification.Name("envmatrix.refreshRequested")
}

/// The single page header used by every top-level screen.
///
/// Layout, left to right: tinted icon badge, title + optional subtitle,
/// caller-supplied accessory (stat chips, primary actions), and a refresh
/// button when `onRefresh` is provided. The refresh button also answers
/// ⌘R via `.envMatrixRefreshRequested`, so every page refreshes the same
/// way from the keyboard.
struct PageHeader<Accessory: View>: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let tint: Color
    let isRefreshing: Bool
    let onRefresh: (() -> Void)?
    let accessory: Accessory

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        tint: Color = .accentColor,
        isRefreshing: Bool = false,
        onRefresh: (() -> Void)? = nil,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.isRefreshing = isRefreshing
        self.onRefresh = onRefresh
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            iconBadge
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title2.bold())
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 12)
            accessory
            if let onRefresh {
                Button(action: onRefresh) {
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                    } else {
                        Label(L("common.refresh"), systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isRefreshing)
                .help(L("page.refresh.help"))
                .onReceive(NotificationCenter.default.publisher(for: .envMatrixRefreshRequested)) { _ in
                    if !isRefreshing { onRefresh() }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isHeader)
    }

    private var iconBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.95), tint.opacity(0.65)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 36, height: 36)
                .shadow(color: tint.opacity(0.30), radius: 3, x: 0, y: 1.5)
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
        }
        .accessibilityHidden(true)
    }
}
