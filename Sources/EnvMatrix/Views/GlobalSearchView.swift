import SwiftUI

/// A modal "spotlight-style" palette that searches across every package
/// manager currently supported by the app.
///
/// Presented as a `.sheet` from `RootView` and driven by the `⌘F` shortcut
/// registered on the main window scene.
public struct GlobalSearchView: View {
    @EnvironmentObject private var navigator: AppNavigator
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = GlobalSearchViewModel()
    @FocusState private var searchFieldFocused: Bool

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(width: 620, height: 480)
        .onAppear {
            searchFieldFocused = true
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.title3)
                .foregroundStyle(.secondary)
            TextField(L("globalSearch.placeholder"), text: Binding(
                get: { viewModel.query },
                set: { viewModel.queryDidChange($0) }
            ))
            .textFieldStyle(.plain)
            .font(.title3)
            .focused($searchFieldFocused)
            .onSubmit { activateFirstResult() }

            if viewModel.isSearching {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.query.trimmingCharacters(in: .whitespaces).isEmpty {
            emptyPromptView
        } else if viewModel.results.isEmpty && !viewModel.isSearching {
            noResultsView
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2, pinnedViews: [.sectionHeaders]) {
                    ForEach(groupedResults, id: \.source) { group in
                        Section(header: sectionHeader(for: group.source,
                                                      count: group.hits.count)) {
                            ForEach(group.hits) { hit in
                                resultRow(hit)
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    /// Sources present in the current result set, preserved in the fixed
    /// `SearchHit.Source.allCases` order (brew, maven, go, node) so the
    /// palette layout stays stable as the user types.
    private var groupedResults: [(source: SearchHit.Source, hits: [SearchHit])] {
        let bucketed = Dictionary(grouping: viewModel.results, by: { $0.source })
        return SearchHit.Source.allCases.compactMap { source in
            guard let hits = bucketed[source], !hits.isEmpty else { return nil }
            return (source, hits)
        }
    }

    private func sectionHeader(for source: SearchHit.Source, count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon(for: source))
                .foregroundStyle(color(for: source))
            Text(label(for: source))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(color(for: source).opacity(0.18),
                            in: Capsule())
                .foregroundStyle(color(for: source))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(.regularMaterial)
    }

    private var emptyPromptView: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text(L("globalSearch.hint.title"))
                .font(.headline)
            Text(L("globalSearch.hint.subtitle"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var noResultsView: some View {
        VStack(spacing: 8) {
            Image(systemName: "questionmark.folder")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(L("globalSearch.noResults"))
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resultRow(_ hit: SearchHit) -> some View {
        Button {
            open(hit)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon(for: hit.source))
                    .foregroundStyle(color(for: hit.source))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(hit.title)
                        .font(.body)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(label(for: hit.source))
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(color(for: hit.source).opacity(0.15),
                                        in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(color(for: hit.source))
                        if let subtitle = hit.subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right.square")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private func activateFirstResult() {
        if let first = viewModel.results.first {
            open(first)
        }
    }

    private func open(_ hit: SearchHit) {
        let target: NavigationItem
        switch hit.source {
        case .brew:   target = .packagesBrew
        case .maven:  target = .packagesMaven
        case .go:     target = .packagesGo
        case .node:   target = .packagesNode
        case .python: target = .packagesPython
        }
        navigator.select(target)
        dismiss()
    }

    private func icon(for source: SearchHit.Source) -> String {
        switch source {
        case .brew:   return "mug"
        case .maven:  return "cube.box"
        case .go:     return "chevron.left.forwardslash.chevron.right"
        case .node:   return "leaf.circle.fill"
        case .python: return "shippingbox.and.arrow.backward"
        }
    }

    private func color(for source: SearchHit.Source) -> Color {
        switch source {
        case .brew:   return .orange
        case .maven:  return .indigo
        case .go:     return .cyan
        case .node:   return .green
        case .python: return .yellow
        }
    }

    private func label(for source: SearchHit.Source) -> String {
        switch source {
        case .brew:   return L("globalSearch.source.brew")
        case .maven:  return L("globalSearch.source.maven")
        case .go:     return L("globalSearch.source.go")
        case .node:   return L("globalSearch.source.node")
        case .python: return L("globalSearch.source.python")
        }
    }
}
