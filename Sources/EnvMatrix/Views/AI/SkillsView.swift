import SwiftUI

public struct SkillsView: View {
    @StateObject private var vm = SkillsViewModel()
    @EnvironmentObject private var localization: LocalizationManager
    @State private var collapsedSources: Set<String> = []

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
            if vm.skills.isEmpty {
                emptyView
            } else {
                List {
                    ForEach(groupedSkills, id: \.source) { group in
                        Section {
                            if !collapsedSources.contains(group.source) {
                                ForEach(group.skills) { skill in
                                    row(for: skill)
                                }
                            }
                        } header: {
                            groupHeader(source: group.source, count: group.skills.count)
                        }
                    }
                }
                .listStyle(.inset)
            }
            if let msg = vm.errorMessage {
                StatusBanner(.error, msg, onDismiss: { vm.errorMessage = nil })
            }
        }
        .navigationTitle(L("skills.title"))
        .task { vm.refresh() }
    }

    private var groupedSkills: [(source: String, skills: [Skill])] {
        let bucketed = Dictionary(grouping: vm.skills) { skill -> String in
            let trimmed = skill.source.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "__unknown__" : trimmed
        }
        return bucketed
            .map { (source: $0.key, skills: $0.value.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) }
            .sorted { lhs, rhs in
                if lhs.source == "__unknown__" { return false }
                if rhs.source == "__unknown__" { return true }
                return lhs.source.localizedCaseInsensitiveCompare(rhs.source) == .orderedAscending
            }
    }

    private func groupHeader(source: String, count: Int) -> some View {
        let isCollapsed = collapsedSources.contains(source)
        let title = source == "__unknown__" ? L("skills.source.unknown") : source.uppercased()
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if isCollapsed {
                    collapsedSources.remove(source)
                } else {
                    collapsedSources.insert(source)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 10)
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(count)")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.purple.opacity(0.18), in: Capsule())
                    .foregroundStyle(.purple)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        PageHeader(
            title: L("skills.title"),
            subtitle: L("skills.subtitle"),
            systemImage: NavigationItem.aiSkills.systemImage,
            tint: NavigationItem.aiSkills.tint,
            onRefresh: { vm.refresh() }
        )
    }

    private var emptyView: some View {
        EmptyStateView(
            systemImage: "sparkles",
            title: L("skills.empty.title"),
            subtitle: L("skills.empty.subtitle")
        )
    }

    @ViewBuilder
    private func row(for skill: Skill) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(skill.name).font(.headline)
                Text(skill.path.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { skill.isEnabled },
                set: { _ in vm.toggle(skill) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button(L("skills.revealInFinder")) { vm.revealInFinder(skill) }
            Divider()
            Button(L("skills.delete"), role: .destructive) { vm.delete(skill) }
        }
    }
}
