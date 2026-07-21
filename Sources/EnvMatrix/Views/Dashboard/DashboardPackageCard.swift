import SwiftUI

/// A dashboard tile for a package manager (Homebrew / Maven / Go / npm).
///
/// Displays cache size, a subtle attention dot when the cache exceeds the
/// configured cleanup threshold, and navigates to the corresponding page
/// on click.
struct DashboardPackageCard: View {
    let snapshot: DashboardViewModel.PackageSnapshot
    let action: () -> Void
    @State private var isHovering = false

    private var tint: Color {
        switch snapshot.kind {
        case .brew:  return .orange
        case .maven: return .blue
        case .go:    return .cyan
        case .node:  return .green
        }
    }

    private var iconName: String {
        switch snapshot.kind {
        case .brew:  return "cube.box.fill"
        case .maven: return "shippingbox.fill"
        case .go:    return "shippingbox.circle"
        case .node:  return "leaf.circle.fill"
        }
    }

    private var title: String {
        switch snapshot.kind {
        case .brew:  return L("nav.homebrew")
        case .maven: return L("nav.mavenRepo")
        case .go:    return L("nav.goRepo")
        case .node:  return L("nav.nodeRepo")
        }
    }

    private var sizeText: String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: snapshot.cacheBytes)
    }

    var body: some View {
        Button(action: action) {
            cardBody
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onHover { hovering in
            isHovering = hovering
            #if canImport(AppKit)
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            #endif
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(title) \(sizeText)"))
        .accessibilityHint(Text(L("dashboard.card.openHint")))
        .accessibilityAddTraits(.isButton)
    }

    private var cardBody: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.95), tint.opacity(0.62)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                        .shadow(color: tint.opacity(0.35), radius: 4, x: 0, y: 2)
                    Image(systemName: iconName)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                }
                if snapshot.needsAttention {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                        .overlay(
                            Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5)
                        )
                        .offset(x: 2, y: -2)
                        .accessibilityLabel(Text(L("dashboard.attention")))
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(sizeText)
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(snapshot.needsAttention
                     ? L("dashboard.package.needsCleanup")
                     : L("dashboard.package.cacheSize"))
                    .font(.caption)
                    .foregroundStyle(snapshot.needsAttention ? Color.red : Color.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .opacity(isHovering ? 1.0 : 0.5)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(tint.opacity(0.22), lineWidth: 0.5)
        )
        .shadow(color: tint.opacity(isHovering ? 0.22 : 0.10), radius: isHovering ? 10 : 4, x: 0, y: isHovering ? 6 : 2)
        .scaleEffect(isHovering ? 1.01 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovering)
    }
}

/// Neutral, non-interactive placeholder shown in the Dashboard's Package
/// Managers grid while the first (or a manually-triggered) scan is still
/// running. Kept structurally identical to `DashboardPackageCard` so the
/// grid does not visibly reflow when real data arrives.
struct DashboardPackageCardSkeleton: View {
    @State private var pulse = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(pulse ? 0.18 : 0.32))
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(pulse ? 0.18 : 0.32))
                    .frame(width: 90, height: 10)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(pulse ? 0.18 : 0.32))
                    .frame(width: 60, height: 18)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(pulse ? 0.14 : 0.24))
                    .frame(width: 100, height: 8)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 0.5)
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .accessibilityHidden(true)
    }
}
