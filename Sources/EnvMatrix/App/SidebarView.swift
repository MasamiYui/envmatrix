import SwiftUI

public struct SidebarView: View {
    @Binding var selection: NavigationItem?
    @EnvironmentObject private var localization: LocalizationManager
    @ObservedObject private var installed = InstalledRuntimesStore.shared
    @State private var filter: String = ""
    /// Section ids the user has collapsed; persisted across launches.
    @AppStorage("sidebar.collapsedSections") private var collapsedRaw: String = ""
    /// Whether the "not installed" runtime subgroup is expanded.
    @AppStorage("sidebar.showAllRuntimes") private var showAllRuntimes: Bool = false

    public init(selection: Binding<NavigationItem?>) {
        self._selection = selection
    }

    public var body: some View {
        List(selection: $selection) {
            if isFiltering {
                filteredRows
            } else {
                ForEach(NavigationItem.allSections, id: \.id) { section in
                    sectionView(section)
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $filter, placement: .sidebar, prompt: L("sidebar.filter"))
        .onAppear { installed.refreshIfNeeded() }
        // Hard floor: SwiftUI has been observed collapsing the sidebar column
        // below its `.navigationSplitViewColumnWidth(min:)` value when the
        // window is opened at just above the aggregate minimum. Pinning the
        // *view* itself guarantees the column can never render narrower than
        // 220pt regardless of the split-view arithmetic.
        .frame(minWidth: 220, idealWidth: 240, maxWidth: 320)
    }

    // MARK: - Sections

    @ViewBuilder
    private func sectionView(_ section: NavigationSection) -> some View {
        let collapsed = isCollapsed(section.id)
        Section {
            if !collapsed {
                if section.id == NavigationSection.devEnvironmentsID {
                    runtimeRows(section.items)
                } else {
                    ForEach(section.items) { item in
                        row(item)
                    }
                }
            }
        } header: {
            sectionHeader(title: section.title, collapsed: collapsed) {
                toggle(section.id)
            }
        }
    }

    /// Runtimes with an active version are always visible; the rest sit
    /// behind a "Not installed (n)" disclosure so a typical sidebar shows
    /// three or four runtimes rather than twelve.
    @ViewBuilder
    private func runtimeRows(_ items: [NavigationItem]) -> some View {
        let present = items.filter { isPresent($0) }
        let absent = items.filter { !isPresent($0) }
        ForEach(present) { item in
            row(item)
        }
        if !absent.isEmpty {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { showAllRuntimes.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showAllRuntimes ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .frame(width: 10)
                    Text(String(format: L("sidebar.notInstalled"), absent.count))
                        .font(.callout)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
            if showAllRuntimes {
                ForEach(absent) { item in
                    row(item, dimmed: true)
                }
            }
        }
    }

    private func isPresent(_ item: NavigationItem) -> Bool {
        if case .devEnv(let kind) = item { return installed.isInstalled(kind) }
        return true
    }

    private func sectionHeader(title: String, collapsed: Bool, onToggle: @escaping () -> Void) -> some View {
        Button(action: onToggle) {
            HStack(spacing: 4) {
                Text(title)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .rotationEffect(.degrees(collapsed ? -90 : 0))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(collapsed ? L("sidebar.expand") : L("sidebar.collapse"))
    }

    // MARK: - Rows

    private func row(_ item: NavigationItem, dimmed: Bool = false) -> some View {
        NavigationLink(value: item) {
            Label {
                Text(item.displayName)
            } icon: {
                Image(systemName: item.systemImage)
                    .foregroundStyle(dimmed ? AnyShapeStyle(.tertiary) : AnyShapeStyle(item.tint))
            }
            .opacity(dimmed ? 0.75 : 1)
        }
    }

    // MARK: - Filtering

    private var isFiltering: Bool {
        !filter.trimmingCharacters(in: .whitespaces).isEmpty
    }

    @ViewBuilder
    private var filteredRows: some View {
        let needle = filter.trimmingCharacters(in: .whitespaces)
        let hits = NavigationItem.allCases.filter { $0.matches(needle) }
        if hits.isEmpty {
            Text(L("sidebar.noMatches"))
                .foregroundStyle(.secondary)
                .font(.callout)
        } else {
            ForEach(hits) { item in
                row(item)
            }
        }
    }

    // MARK: - Collapse state

    private var collapsedSet: Set<String> {
        Set(collapsedRaw.split(separator: ",").map(String.init))
    }

    private func isCollapsed(_ id: String) -> Bool {
        collapsedSet.contains(id)
    }

    private func toggle(_ id: String) {
        var set = collapsedSet
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
        withAnimation(.easeInOut(duration: 0.15)) {
            collapsedRaw = set.sorted().joined(separator: ",")
        }
    }
}

extension NavigationItem {
    /// Case-insensitive match against the localized name, the English
    /// name and the stable id, so "npm", "node" and "Node 全局环境" all hit.
    func matches(_ needle: String) -> Bool {
        let n = needle.lowercased()
        if displayName.lowercased().contains(n) { return true }
        if id.lowercased().contains(n) { return true }
        for alias in searchAliases where alias.lowercased().contains(n) { return true }
        return false
    }

    private var searchAliases: [String] {
        switch self {
        case .dashboard: return ["dashboard", "overview", "仪表盘", "总览"]
        case .devEnv(let kind): return [kind.displayName, kind.rawValue, kind.binaryName]
        case .packagesBrew: return ["homebrew", "brew", "cask", "formula"]
        case .packagesMaven: return ["maven", "java", "gradle", "m2"]
        case .packagesGo: return ["go", "goproxy", "gomodcache"]
        case .packagesNode: return ["node", "npm", "npmrc", "registry"]
        case .packagesPython: return ["python", "pip", "pypi"]
        case .packagesRuby: return ["ruby", "gem", "rubygems"]
        case .packagesRust: return ["rust", "cargo", "crates"]
        case .packagesPhp: return ["php", "composer", "packagist"]
        case .packagesDotnet: return ["dotnet", ".net", "nuget"]
        case .packagesUv: return ["uv", "python", "tool"]
        case .packagesPnpm: return ["pnpm", "node", "store"]
        case .packagesProjectEnv: return ["project", "node_modules", "venv", "target", "项目"]
        case .aiSkills: return ["skills", "ai", "技能"]
        case .aiCLI: return ["cli", "ai", "api key", "model"]
        case .aiMCP: return ["mcp", "model context protocol", "server"]
        case .systemShellEnv: return ["shell", "zsh", "bash", "zshrc", "path", "export"]
        case .systemHosts: return ["hosts", "/etc/hosts", "dns"]
        case .systemLocalApps: return ["apps", "applications", "uninstall", "应用"]
        case .systemContainerContexts: return ["docker", "podman", "container", "image", "容器"]
        case .settings: return ["settings", "preferences", "设置", "偏好"]
        }
    }
}
