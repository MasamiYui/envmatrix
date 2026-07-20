import Foundation
import SwiftUI
import Combine

public enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case en
    case zh

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: return NSLocalizedString("System", comment: "")
        case .en: return "English"
        case .zh: return "中文"
        }
    }
}

public final class LocalizationManager: ObservableObject {
    public static let shared = LocalizationManager()

    @Published public var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.storageKey)
        }
    }

    private static let storageKey = "appLanguagePreference"

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.storageKey) ?? AppLanguage.system.rawValue
        self.language = AppLanguage(rawValue: stored) ?? .system
    }

    public var resolvedCode: String {
        switch language {
        case .en: return "en"
        case .zh: return "zh"
        case .system:
            let pref = Locale.preferredLanguages.first ?? "en"
            if pref.hasPrefix("zh") { return "zh" }
            return "en"
        }
    }

    public func t(_ key: String) -> String {
        let code = resolvedCode
        if let table = L10n.strings[code], let value = table[key] {
            return value
        }
        if let value = L10n.strings["en"]?[key] {
            return value
        }
        return key
    }
}

public func L(_ key: String) -> String {
    LocalizationManager.shared.t(key)
}

public enum L10n {
    public static let strings: [String: [String: String]] = [
        "en": en,
        "zh": zh
    ]

    static let en: [String: String] = [
        "app.name": "EnvMatrix",
        "app.welcome.title": "Welcome to EnvMatrix",
        "app.welcome.subtitle": "Select an item from the sidebar to get started.",
        "app.underConstruction": "This section is under construction.",

        "nav.overview": "Overview",
        "nav.devEnvironments": "Dev Environments",
        "nav.packages": "Packages",
        "nav.aiEnvironments": "AI Environments",
        "nav.system": "System",
        "nav.dashboard": "Dashboard",
        "nav.homebrew": "Homebrew",
        "nav.mavenRepo": "Maven Repository",
        "nav.skills": "Skills",
        "nav.aiCLI": "AI CLI",
        "nav.mcpServers": "MCP Servers",
        "nav.settings": "Settings",

        "dashboard.title": "Dashboard",
        "dashboard.subtitle": "Overview of your local dev & AI environments",
        "dashboard.refresh": "Refresh",
        "dashboard.runtimeSuffix": "Runtime",
        "dashboard.current": "Current",
        "dashboard.notSet": "Not Set",
        "dashboard.system": "System",
        "dashboard.installed": "installed",
        "dashboard.configured": "configured",
        "dashboard.storage": "Storage",
        "dashboard.skills": "Skills",
        "dashboard.mcpServers": "MCP Servers",
        "dashboard.activeRuntimes": "Active Runtimes",
        "dashboard.managed": "Managed",
        "dashboard.section.runtimes": "Runtimes",
        "dashboard.section.overview": "Overview",
        "dashboard.storage.subtitle": "Used by managed versions",
        "dashboard.card.openHint": "Open details",

        "runtime.installed": "Installed",
        "runtime.available": "Available",
        "runtime.active": "Active",
        "runtime.none": "None",
        "runtime.systemDefault": "System Default",
        "runtime.refresh": "Refresh",
        "runtime.loading": "Loading versions...",
        "runtime.noAvailable": "No available versions.",
        "runtime.noInstalled": "No installed versions. Switch to Available to install one.",
        "runtime.install": "Install",
        "runtime.installedLabel": "Installed",
        "runtime.setActive": "Set Active",
        "runtime.uninstall": "Uninstall",
        "runtime.uninstallTitle": "Uninstall %@?",
        "runtime.cancel": "Cancel",
        "runtime.revealInFinder": "Reveal in Finder",
        "runtime.uninstallSystemMessage": "EnvMatrix will remove the folder:\n%@\n\nIf it was installed via brew / sdkman / nvm / pkg, using its own uninstaller is safer. Paths owned by the OS may require sudo and will be rejected.",
        "runtime.uninstallMessage": "This will remove %@ %@ from your system.",
        "runtime.uninstallSystemTooltip": "Uninstall this system runtime (will confirm before deleting)",
        "runtime.uninstallTooltip": "Uninstall this version",
        "runtime.systemBadge": "System",

        "skills.title": "Skills",
        "skills.refresh": "Refresh",
        "skills.empty.title": "No Skills Found",
        "skills.empty.subtitle": "Configured skills directories are empty.",
        "skills.revealInFinder": "Reveal in Finder",
        "skills.delete": "Delete",

        "cli.title": "AI CLI",
        "cli.save": "Save",
        "cli.selectPrompt": "Select a CLI configuration",
        "cli.selectHint": "Choose a configuration on the left to edit its values.",
        "cli.model": "Model",
        "cli.apiBaseURL": "API Base URL",
        "cli.apiKey": "API Key",

        "mcp.title": "MCP Servers",
        "mcp.add": "Add",
        "mcp.refresh": "Refresh",
        "mcp.empty.title": "No MCP Servers",
        "mcp.empty.subtitle": "Click Add to configure a new server.",
        "mcp.edit": "Edit",
        "mcp.delete": "Delete",
        "mcp.argCount.one": "%d arg",
        "mcp.argCount.many": "%d args",
        "mcp.editor.editTitle": "Edit MCP Server",
        "mcp.editor.addTitle": "Add MCP Server",
        "mcp.editor.basics": "Basics",
        "mcp.editor.name": "Name",
        "mcp.editor.command": "Command",
        "mcp.editor.arguments": "Arguments",
        "mcp.editor.argsPlaceholder": "Comma-separated",
        "mcp.editor.argsHelp": "Values separated by commas, e.g. --port,8080",
        "mcp.editor.envVars": "Environment Variables",
        "mcp.editor.envKey": "KEY",
        "mcp.editor.envValue": "value",
        "mcp.editor.addVariable": "Add Variable",
        "mcp.editor.cancel": "Cancel",
        "mcp.editor.save": "Save",

        "settings.general": "General",
        "settings.logs": "Logs",
        "settings.about": "About",
        "settings.appearance": "Appearance",
        "settings.colorScheme": "Color Scheme",
        "settings.system": "System",
        "settings.light": "Light",
        "settings.dark": "Dark",
        "settings.language": "Language",
        "settings.languageLabel": "Interface Language",
        "settings.mirrors": "Mirror Sources",
        "settings.nodeMirror": "Node.js Mirror",
        "settings.pythonMirror": "Python Mirror",
        "settings.goMirror": "Go Mirror",
        "settings.javaMirror": "Java Mirror",
        "settings.resetDefaults": "Reset to Defaults",
        "settings.entries": "%d entries",
        "settings.clear": "Clear",
        "settings.noLogs": "No log entries.",
        "settings.version": "Version %@",
        "settings.aboutDescription": "A unified macOS control panel for managing developer runtimes and AI development environments.",
        "settings.viewGitHub": "View on GitHub",

        "brew.title": "Homebrew",
        "brew.notInstalled.title": "Homebrew Not Found",
        "brew.notInstalled.subtitle": "EnvMatrix couldn't find a `brew` executable at /opt/homebrew/bin/brew or /usr/local/bin/brew. Install Homebrew to manage packages here.",
        "brew.formulae": "Formulae",
        "brew.casks": "Casks",
        "brew.refresh": "Refresh",
        "brew.loading": "Loading Homebrew inventory…",
        "brew.emptyList": "No packages match the current filters.",
        "brew.searchPlaceholder": "Search name or description",
        "brew.outdatedCount": "%d outdated",
        "brew.upgradeAll": "Upgrade All",
        "brew.cleanup": "Cleanup",
        "brew.update": "brew update",
        "brew.filter.outdatedOnly": "Outdated only",
        "brew.filter.requestedOnly": "Requested only",
        "brew.action.upgrade": "Upgrade",
        "brew.action.uninstall": "Uninstall",
        "brew.action.pin": "Pin",
        "brew.action.unpin": "Unpin",
        "brew.action.openHomepage": "Open Homepage",
        "brew.detail.selectHint": "Select a package to see details.",
        "brew.detail.kind": "Kind",
        "brew.detail.installedVersion": "Installed",
        "brew.detail.latestVersion": "Latest",
        "brew.detail.homepage": "Homepage",
        "brew.detail.autoUpdates": "Auto Updates",
        "brew.detail.installedAt": "Installed At",
        "brew.detail.deprecationReason": "Deprecation",
        "brew.detail.dependencies": "Dependencies",
        "brew.yes": "Yes",
        "brew.no": "No",

        "mavenRepo.title": "Maven Repository",
        "mavenRepo.subtitle": "Manage settings.xml mirrors and local ~/.m2/repository artifacts",
        "mavenRepo.refresh": "Refresh",
        "mavenRepo.addPreset": "Add Preset",
        "mavenRepo.settingsFile": "settings.xml:",
        "mavenRepo.localRepository": "localRepository:",
        "mavenRepo.active": "Active",
        "mavenRepo.mirrorOfFormat": "mirrorOf: %@",
        "mavenRepo.empty.title": "No Mirrors Configured",
        "mavenRepo.empty.subtitle": "Use the + button to add a preset mirror (Aliyun, Tencent, HuaweiCloud, Netease).",
        "mavenRepo.tab.mirrors": "Mirrors",
        "mavenRepo.tab.localArtifacts": "Local Artifacts",
        "mavenRepo.artifact.searchPlaceholder": "Search groupId, artifactId or version",
        "mavenRepo.artifact.countFormat": "%d artifacts",
        "mavenRepo.artifact.totalSizeFormat": "Total: %@",
        "mavenRepo.artifact.versionCountFormat": "%d versions",
        "mavenRepo.artifact.sortByName": "Sort by Name",
        "mavenRepo.artifact.sortBySize": "Sort by Size",
        "mavenRepo.artifact.sortByModified": "Sort by Modified",
        "mavenRepo.artifact.ascending": "Ascending",
        "mavenRepo.artifact.loading": "Scanning local repository…",
        "mavenRepo.artifact.notFound.title": "Local Repository Not Found",
        "mavenRepo.artifact.notFound.subtitle": "No directory at %@\n\nRun a Maven build first to populate ~/.m2/repository.",
        "mavenRepo.artifact.empty.title": "No Artifacts",
        "mavenRepo.artifact.empty.subtitle": "No downloaded artifacts match your search.",
        "mavenRepo.artifact.deleteAll": "Delete all versions",
        "mavenRepo.artifact.confirmDelete": "Delete %@?",
        "mavenRepo.artifact.confirmDeleteVersion": "Delete %@ (%@)?",
        "mavenRepo.artifact.confirmDeleteMessage": "This will remove %@ from disk. This action cannot be undone."
    ]

    static let zh: [String: String] = [
        "app.name": "EnvMatrix",
        "app.welcome.title": "欢迎使用 EnvMatrix",
        "app.welcome.subtitle": "请从左侧边栏选择一项以开始使用。",
        "app.underConstruction": "此模块正在建设中。",

        "nav.overview": "概览",
        "nav.devEnvironments": "开发环境",
        "nav.packages": "包管理",
        "nav.aiEnvironments": "AI 环境",
        "nav.system": "系统",
        "nav.dashboard": "仪表盘",
        "nav.homebrew": "Homebrew",
        "nav.mavenRepo": "Maven 仓库",
        "nav.skills": "技能",
        "nav.aiCLI": "AI 命令行",
        "nav.mcpServers": "MCP 服务器",
        "nav.settings": "设置",

        "dashboard.title": "仪表盘",
        "dashboard.subtitle": "本地开发和 AI 环境的总览",
        "dashboard.refresh": "刷新",
        "dashboard.runtimeSuffix": "运行时",
        "dashboard.current": "当前",
        "dashboard.notSet": "未设置",
        "dashboard.system": "系统",
        "dashboard.installed": "已安装",
        "dashboard.configured": "已配置",
        "dashboard.storage": "存储",
        "dashboard.skills": "技能",
        "dashboard.mcpServers": "MCP 服务器",
        "dashboard.activeRuntimes": "已启用运行时",
        "dashboard.managed": "已托管",
        "dashboard.section.runtimes": "运行时",
        "dashboard.section.overview": "总览",
        "dashboard.storage.subtitle": "托管版本占用",
        "dashboard.card.openHint": "打开详情",

        "runtime.installed": "已安装",
        "runtime.available": "可用版本",
        "runtime.active": "当前",
        "runtime.none": "无",
        "runtime.systemDefault": "系统默认",
        "runtime.refresh": "刷新",
        "runtime.loading": "正在加载版本...",
        "runtime.noAvailable": "没有可用版本。",
        "runtime.noInstalled": "尚未安装任何版本。切换到\"可用版本\"进行安装。",
        "runtime.install": "安装",
        "runtime.installedLabel": "已安装",
        "runtime.setActive": "设为活动",
        "runtime.uninstall": "卸载",
        "runtime.uninstallTitle": "卸载 %@?",
        "runtime.cancel": "取消",
        "runtime.revealInFinder": "在访达中显示",
        "runtime.uninstallSystemMessage": "EnvMatrix 将删除以下文件夹:\n%@\n\n如果它是通过 brew / sdkman / nvm / pkg 安装的，使用其自带的卸载工具会更安全。系统所属的路径可能需要 sudo 权限，将被拒绝。",
        "runtime.uninstallMessage": "此操作将从系统中移除 %@ %@。",
        "runtime.uninstallSystemTooltip": "卸载此系统运行时（删除前会二次确认）",
        "runtime.uninstallTooltip": "卸载此版本",
        "runtime.systemBadge": "系统",

        "skills.title": "技能",
        "skills.refresh": "刷新",
        "skills.empty.title": "未找到技能",
        "skills.empty.subtitle": "配置的技能目录为空。",
        "skills.revealInFinder": "在访达中显示",
        "skills.delete": "删除",

        "cli.title": "AI 命令行",
        "cli.save": "保存",
        "cli.selectPrompt": "请选择一个 CLI 配置",
        "cli.selectHint": "在左侧选择一项配置以编辑其内容。",
        "cli.model": "模型",
        "cli.apiBaseURL": "API 基础地址",
        "cli.apiKey": "API 密钥",

        "mcp.title": "MCP 服务器",
        "mcp.add": "添加",
        "mcp.refresh": "刷新",
        "mcp.empty.title": "暂无 MCP 服务器",
        "mcp.empty.subtitle": "点击\"添加\"以配置新的服务器。",
        "mcp.edit": "编辑",
        "mcp.delete": "删除",
        "mcp.argCount.one": "%d 个参数",
        "mcp.argCount.many": "%d 个参数",
        "mcp.editor.editTitle": "编辑 MCP 服务器",
        "mcp.editor.addTitle": "添加 MCP 服务器",
        "mcp.editor.basics": "基本信息",
        "mcp.editor.name": "名称",
        "mcp.editor.command": "命令",
        "mcp.editor.arguments": "参数",
        "mcp.editor.argsPlaceholder": "以逗号分隔",
        "mcp.editor.argsHelp": "多个值用英文逗号分隔，例如: --port,8080",
        "mcp.editor.envVars": "环境变量",
        "mcp.editor.envKey": "键",
        "mcp.editor.envValue": "值",
        "mcp.editor.addVariable": "添加变量",
        "mcp.editor.cancel": "取消",
        "mcp.editor.save": "保存",

        "settings.general": "通用",
        "settings.logs": "日志",
        "settings.about": "关于",
        "settings.appearance": "外观",
        "settings.colorScheme": "配色方案",
        "settings.system": "跟随系统",
        "settings.light": "浅色",
        "settings.dark": "深色",
        "settings.language": "语言",
        "settings.languageLabel": "界面语言",
        "settings.mirrors": "镜像源",
        "settings.nodeMirror": "Node.js 镜像",
        "settings.pythonMirror": "Python 镜像",
        "settings.goMirror": "Go 镜像",
        "settings.javaMirror": "Java 镜像",
        "settings.resetDefaults": "恢复默认",
        "settings.entries": "共 %d 条",
        "settings.clear": "清除",
        "settings.noLogs": "暂无日志。",
        "settings.version": "版本 %@",
        "settings.aboutDescription": "一款统一的 macOS 控制面板，用于管理开发者运行时和 AI 开发环境。",
        "settings.viewGitHub": "在 GitHub 上查看",

        "brew.title": "Homebrew",
        "brew.notInstalled.title": "未找到 Homebrew",
        "brew.notInstalled.subtitle": "EnvMatrix 在 /opt/homebrew/bin/brew 或 /usr/local/bin/brew 未找到 brew 可执行文件。请先安装 Homebrew。",
        "brew.formulae": "Formula",
        "brew.casks": "Cask",
        "brew.refresh": "刷新",
        "brew.loading": "正在加载 Homebrew 清单…",
        "brew.emptyList": "当前筛选条件下没有匹配的包。",
        "brew.searchPlaceholder": "搜索名称或描述",
        "brew.outdatedCount": "%d 个可升级",
        "brew.upgradeAll": "全部升级",
        "brew.cleanup": "清理缓存",
        "brew.update": "更新元数据",
        "brew.filter.outdatedOnly": "仅显示可升级",
        "brew.filter.requestedOnly": "仅显示手动安装",
        "brew.action.upgrade": "升级",
        "brew.action.uninstall": "卸载",
        "brew.action.pin": "锁定版本",
        "brew.action.unpin": "解锁版本",
        "brew.action.openHomepage": "打开主页",
        "brew.detail.selectHint": "在左侧选择一个包以查看详情。",
        "brew.detail.kind": "类型",
        "brew.detail.installedVersion": "已安装",
        "brew.detail.latestVersion": "最新版本",
        "brew.detail.homepage": "主页",
        "brew.detail.autoUpdates": "自动更新",
        "brew.detail.installedAt": "安装时间",
        "brew.detail.deprecationReason": "废弃原因",
        "brew.detail.dependencies": "依赖",
        "brew.yes": "是",
        "brew.no": "否",

        "mavenRepo.title": "Maven 仓库",
        "mavenRepo.subtitle": "管理 settings.xml 镜像与本地 ~/.m2/repository 依赖",
        "mavenRepo.refresh": "刷新",
        "mavenRepo.addPreset": "添加预设",
        "mavenRepo.settingsFile": "settings.xml：",
        "mavenRepo.localRepository": "本地仓库：",
        "mavenRepo.active": "已启用",
        "mavenRepo.mirrorOfFormat": "mirrorOf：%@",
        "mavenRepo.empty.title": "尚未配置镜像",
        "mavenRepo.empty.subtitle": "点击右上角 + 号添加预设镜像（阿里云 / 腾讯云 / 华为云 / 网易）。",
        "mavenRepo.tab.mirrors": "镜像源",
        "mavenRepo.tab.localArtifacts": "本地依赖",
        "mavenRepo.artifact.searchPlaceholder": "搜索 groupId、artifactId 或 version",
        "mavenRepo.artifact.countFormat": "共 %d 个依赖",
        "mavenRepo.artifact.totalSizeFormat": "总计：%@",
        "mavenRepo.artifact.versionCountFormat": "%d 个版本",
        "mavenRepo.artifact.sortByName": "按名称排序",
        "mavenRepo.artifact.sortBySize": "按大小排序",
        "mavenRepo.artifact.sortByModified": "按修改时间排序",
        "mavenRepo.artifact.ascending": "升序",
        "mavenRepo.artifact.loading": "正在扫描本地仓库…",
        "mavenRepo.artifact.notFound.title": "未找到本地仓库",
        "mavenRepo.artifact.notFound.subtitle": "路径 %@ 不存在。\n\n请先运行一次 Maven 构建以生成 ~/.m2/repository。",
        "mavenRepo.artifact.empty.title": "暂无依赖",
        "mavenRepo.artifact.empty.subtitle": "当前搜索条件下没有下载的依赖。",
        "mavenRepo.artifact.deleteAll": "删除所有版本",
        "mavenRepo.artifact.confirmDelete": "删除 %@？",
        "mavenRepo.artifact.confirmDeleteVersion": "删除 %@（%@）？",
        "mavenRepo.artifact.confirmDeleteMessage": "此操作将从磁盘移除 %@，无法撤销。"
    ]
}
