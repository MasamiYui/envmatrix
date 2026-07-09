import SwiftUI

public struct SkillsView: View {
    @StateObject private var vm = SkillsViewModel()

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
        .navigationTitle("Skills")
        .task { vm.refresh() }
    }

    private var header: some View {
        HStack {
            Text("Skills")
                .font(.title.bold())
            Spacer()
            Button("Refresh") { vm.refresh() }
        }
        .padding()
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Skills Found")
                .font(.title2.bold())
            Text("Configured skills directories are empty.")
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
            Button("Reveal in Finder") { vm.revealInFinder(skill) }
            Divider()
            Button("Delete", role: .destructive) { vm.delete(skill) }
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
