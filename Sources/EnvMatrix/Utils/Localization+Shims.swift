import Foundation

extension L10n {
    static let enShims: [String: String] = [
        "shims.banner.title": "Terminal won't see the active version yet",
        "shims.banner.body": "\"Set Active\" points ~/.envmatrix/shims at the chosen version, but that folder is not on your shell PATH. Add the line below to %@ (a backup is created first), then open a new terminal.",
        "shims.banner.copy": "Copy",
        "shims.banner.copied": "Copied",
        "shims.banner.addToRc": "Add to %@",
        "shims.banner.done.title": "PATH line written to %@",
        "shims.banner.done.body": "Open a new terminal window (or run `source` on the file) for the change to take effect. A .envmatrix.bak backup was saved next to it.",
        "shims.banner.reveal": "Reveal",
        "banner.diagnostics": "Diagnostics",
        "banner.diagnostics.help": "Open Settings › Diagnostics to export a report about this environment",
        "banner.dismiss": "Dismiss",
        "page.refresh.help": "Refresh (⌘R)",
        "menu.settings": "Settings…",
        "menu.findInPackages": "Find in Packages…",
        "menu.refresh": "Refresh",
        "skills.subtitle": "Skill folders discovered for your AI assistants",
        "mcp.subtitle": "Model Context Protocol servers, grouped by transport",
        "cli.subtitle": "Model, API base URL and key for each AI command-line tool",
        "shellEnv.subtitle": "Edit rc files with structured or raw views; backups are automatic",
        "hosts.subtitle": "Profiles for /etc/hosts; applying asks for administrator rights",
        "localApps.subtitle": "Applications in /Applications and ~/Applications with their leftovers",
        "settings.subtitle": "Appearance, language, mirrors, backups, diagnostics and logs"
    ]

    static let zhShims: [String: String] = [
        "shims.banner.title": "终端暂时还看不到你切换的版本",
        "shims.banner.body": "“设为活动”只是把 ~/.envmatrix/shims 指向所选版本，但该目录不在你的 shell PATH 中。把下面这行加入 %@（写入前会自动备份），然后新开一个终端窗口。",
        "shims.banner.copy": "复制",
        "shims.banner.copied": "已复制",
        "shims.banner.addToRc": "写入 %@",
        "shims.banner.done.title": "已把 PATH 配置写入 %@",
        "shims.banner.done.body": "新开一个终端窗口（或对该文件执行 source）后生效。原文件已备份为 .envmatrix.bak。",
        "shims.banner.reveal": "在访达中显示",
        "banner.diagnostics": "诊断报告",
        "banner.diagnostics.help": "打开 设置 › 诊断，导出当前环境的诊断报告",
        "banner.dismiss": "关闭",
        "page.refresh.help": "刷新（⌘R）",
        "menu.settings": "设置…",
        "menu.findInPackages": "在包中查找…",
        "menu.refresh": "刷新",
        "skills.subtitle": "为 AI 助手发现的技能目录",
        "mcp.subtitle": "Model Context Protocol 服务器，按传输方式分组",
        "cli.subtitle": "各 AI 命令行工具的模型、API 地址与密钥",
        "shellEnv.subtitle": "以结构化或原文视图编辑 rc 文件，保存前自动备份",
        "hosts.subtitle": "/etc/hosts 的多份 Profile，应用到系统时会请求管理员权限",
        "localApps.subtitle": "/Applications 与 ~/Applications 中的应用及其残留文件",
        "settings.subtitle": "外观、语言、镜像、备份、诊断与日志"
    ]
}
