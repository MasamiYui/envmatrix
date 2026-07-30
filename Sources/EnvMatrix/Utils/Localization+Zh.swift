import Foundation

extension L10n {
    static let zh: [String: String] = [:]

    static let zhUv: [String: String] = [
        "uvRepo.title": "uv 仓库",
        "uvRepo.subtitle": "管理 uv 镜像源、全局工具与缓存",
        "uvRepo.tab.registry": "镜像源",
        "uvRepo.tab.globalTools": "全局工具",
        "uvRepo.tab.cache": "缓存",

        "uvRepo.registry.current": "当前 index：",
        "uvRepo.registry.presets": "预设镜像",
        "uvRepo.registry.custom": "自定义 URL",
        "uvRepo.registry.apply": "应用",
        "uvRepo.registry.confirmApply": "确定要切换 uv 镜像吗？",

        "uvRepo.msg.saved": "已保存",
        "uvRepo.msg.invalidURL": "URL 必须以 http:// 或 https:// 开头",

        "uvRepo.tools.title": "全局工具",
        "uvRepo.tools.search": "搜索工具",
        "uvRepo.tools.total": "共 %d 个",
        "uvRepo.tools.uninstall": "卸载",
        "uvRepo.tools.uninstallTitle": "确定要卸载该 uv 工具吗？",
        "uvRepo.tools.uninstallMessage": "将执行 `uv tool uninstall <name>`。",
        "uvRepo.tools.empty": "未安装任何 uv 工具",

        "uvRepo.cache.title": "缓存",
        "uvRepo.cache.path": "缓存目录",
        "uvRepo.cache.size": "缓存大小",
        "uvRepo.cache.clean": "清理缓存",
        "uvRepo.cache.cleaned": "缓存已清理",
        "uvRepo.cache.confirmClean": "确定要清理 uv 缓存吗？",

        "uvRepo.missing.title": "未检测到 uv",
        "uvRepo.missing.subtitle": "PATH 上未找到 `uv` 命令。请先执行 `brew install uv` 后重试。",

        "notify.uv.cache.title": "uv 缓存已清理",
        "notify.uv.cache.body": "本地 uv 缓存已经全部释放。"
    ]

    static let zhPnpm: [String: String] = [
        "pnpmRepo.title": "pnpm 仓库",
        "pnpmRepo.subtitle": "管理 pnpm 镜像源、全局包与内容寻址 store",
        "pnpmRepo.tab.registry": "镜像源",
        "pnpmRepo.tab.globalPkg": "全局包",
        "pnpmRepo.tab.store": "Store",

        "pnpmRepo.registry.current": "当前 registry：",
        "pnpmRepo.registry.presets": "预设镜像",
        "pnpmRepo.registry.custom": "自定义 URL",
        "pnpmRepo.registry.apply": "应用",
        "pnpmRepo.registry.confirmApply": "确定要切换 pnpm 镜像吗？",

        "pnpmRepo.msg.saved": "已保存",
        "pnpmRepo.msg.invalidURL": "URL 必须以 http:// 或 https:// 开头",

        "pnpmRepo.pkg.title": "全局包",
        "pnpmRepo.pkg.search": "搜索全局包",
        "pnpmRepo.pkg.total": "共 %d 个",
        "pnpmRepo.pkg.uninstall": "卸载",
        "pnpmRepo.pkg.confirmDelete": "确定要卸载该 pnpm 全局包吗？",
        "pnpmRepo.pkg.empty": "未安装任何 pnpm 全局包",

        "pnpmRepo.store.title": "Store",
        "pnpmRepo.store.path": "Store 目录",
        "pnpmRepo.store.size": "Store 大小",
        "pnpmRepo.store.prune": "清理 Store",
        "pnpmRepo.store.pruned": "Store 已清理",
        "pnpmRepo.store.confirmPrune": "确定要清理 pnpm store 吗？",

        "pnpmRepo.missing.title": "未检测到 pnpm",
        "pnpmRepo.missing.subtitle": "PATH 上未找到 `pnpm` 命令。请先执行 `brew install pnpm` 后重试。",

        "notify.pnpm.store.title": "pnpm store 已清理",
        "notify.pnpm.store.body": "本地 pnpm store 已经全部释放。"
    ]
}
