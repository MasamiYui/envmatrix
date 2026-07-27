import SwiftUI

public struct ContainerOverviewCard: View {
    @StateObject private var vm: ContainerOverviewViewModel
    @EnvironmentObject private var navigator: AppNavigator
    @State private var isHovering = false

    public init(viewModel: ContainerOverviewViewModel? = nil) {
        if let existing = viewModel {
            _vm = StateObject(wrappedValue: existing)
        } else {
            _vm = StateObject(wrappedValue: ContainerOverviewViewModel())
        }
    }

    public var body: some View {
        Button(action: openContainersTab) {
            cardBody
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onHover { hovering in
            isHovering = hovering
            #if canImport(AppKit)
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
            #endif
        }
        .task { await vm.refresh() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(L("dashboard.card.containers.title")))
        .accessibilityHint(Text(L("dashboard.card.openHint")))
        .accessibilityAddTraits(.isButton)
    }

    private func openContainersTab() {
        navigator.select(.systemContainerContexts)
        NotificationCenter.default.post(
            name: Notification.Name("ContainerContextsSetTab"),
            object: nil,
            userInfo: ["tab": "containers"]
        )
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(L("dashboard.card.containers.title"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if vm.isLoading {
                    ProgressView().controlSize(.small)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .opacity(isHovering ? 1.0 : 0.5)
            }
            engineRow(
                icon: "shippingbox",
                tint: .blue,
                engineName: "Docker",
                contextLabel: L("dashboard.card.containers.dockerContext"),
                contextName: vm.dockerContextName,
                images: vm.dockerImages,
                running: vm.dockerRunning,
                stopped: vm.dockerStopped
            )
            Divider().opacity(0.4)
            engineRow(
                icon: "shippingbox.fill",
                tint: .purple,
                engineName: "Podman",
                contextLabel: L("dashboard.card.containers.podmanConn"),
                contextName: vm.podmanConnectionName,
                images: vm.podmanImages,
                running: vm.podmanRunning,
                stopped: vm.podmanStopped
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(isHovering ? 0.10 : 0.05), radius: isHovering ? 10 : 4, x: 0, y: isHovering ? 6 : 2)
        .scaleEffect(isHovering ? 1.01 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovering)
    }

    @ViewBuilder
    private func engineRow(
        icon: String,
        tint: Color,
        engineName: String,
        contextLabel: String,
        contextName: String?,
        images: Int,
        running: Int,
        stopped: Int
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.95), tint.opacity(0.62)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 34, height: 34)
                    .shadow(color: tint.opacity(0.35), radius: 3, x: 0, y: 2)
                Image(systemName: icon)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(engineName)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(contextName ?? "-")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                HStack(spacing: 10) {
                    countChip(label: L("dashboard.card.containers.images"), value: images, tint: tint)
                    countChip(label: L("dashboard.card.containers.running"), value: running, tint: .green)
                    countChip(label: L("dashboard.card.containers.stopped"), value: stopped, tint: .orange)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(engineName) \(contextLabel) \(contextName ?? "-")"))
    }

    private func countChip(label: String, value: Int, tint: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(value)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(tint.opacity(0.10), in: Capsule(style: .continuous))
    }
}
