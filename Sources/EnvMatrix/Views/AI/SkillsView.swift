import SwiftUI

public struct SkillsView: View {
    @StateObject private var vm = SkillsViewModel()
    @EnvironmentObject private var localization: LocalizationManager

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
            if vm.skills.isEmpty {
                emptyView
            } else {
                List(vm.skills) { skill in
                    row(for: skill)
                }
                .listStyle(.inset)
            }
            if let msg = vm.errorMessage {
                errorBanner(msg)
            }
        }
        .navigationTitle(L("skills.title"))
        .task { vm.refresh() }
    }

    private var header: some View {
        HStack {
            Text(L("skills.title"))
                .font(.title.bold())
            Spacer()
            Button(L("skills.refresh")) { vm.refresh() }
        }
        .padding()
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(L("skills.empty.title"))
                .font(.title2.bold())
            Text(L("skills.empty.subtitle"))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
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
                Text(skill.source.uppercased())
                    .font(.caption2)
                    .padding(.horizontal, 4)
                    .background(Capsule().fill(Color.gray.opacity(0.2)))
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

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(msg)
                .font(.callout)
                .lineLimit(3)
            Spacer()
            Button {
                vm.errorMessage = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
    }
}
