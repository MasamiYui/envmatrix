import Foundation

extension L10n {
    static let en: [String: String] = [:]

    static let enUv: [String: String] = [
        "uvRepo.title": "uv Repository",
        "uvRepo.subtitle": "Manage uv index, global tools and cache",
        "uvRepo.tab.registry": "Registry",
        "uvRepo.tab.globalTools": "Global Tools",
        "uvRepo.tab.cache": "Cache",

        "uvRepo.registry.current": "Current index:",
        "uvRepo.registry.presets": "Preset mirrors",
        "uvRepo.registry.custom": "Custom URL",
        "uvRepo.registry.apply": "Apply",
        "uvRepo.registry.confirmApply": "Switch the uv index?",

        "uvRepo.msg.saved": "Saved",
        "uvRepo.msg.invalidURL": "URL must start with http:// or https://",

        "uvRepo.tools.title": "Global Tools",
        "uvRepo.tools.search": "Search tools",
        "uvRepo.tools.total": "%d total",
        "uvRepo.tools.uninstall": "Uninstall",
        "uvRepo.tools.uninstallTitle": "Uninstall this uv tool?",
        "uvRepo.tools.uninstallMessage": "This will run `uv tool uninstall <name>`.",
        "uvRepo.tools.empty": "No uv tools installed",

        "uvRepo.cache.title": "Cache",
        "uvRepo.cache.path": "Cache directory",
        "uvRepo.cache.size": "Cache size",
        "uvRepo.cache.clean": "Clean cache",
        "uvRepo.cache.cleaned": "Cache cleaned",
        "uvRepo.cache.confirmClean": "Clean the uv cache?",

        "uvRepo.missing.title": "uv Not Found",
        "uvRepo.missing.subtitle": "The `uv` command is not on PATH. Install it with `brew install uv` and try again.",

        "notify.uv.cache.title": "uv cache cleaned",
        "notify.uv.cache.body": "The local uv cache has been fully released."
    ]

    static let enPnpm: [String: String] = [
        "pnpmRepo.title": "pnpm Repository",
        "pnpmRepo.subtitle": "Manage pnpm registry, global packages and content-addressable store",
        "pnpmRepo.tab.registry": "Registry",
        "pnpmRepo.tab.globalPkg": "Global Packages",
        "pnpmRepo.tab.store": "Store",

        "pnpmRepo.registry.current": "Current registry:",
        "pnpmRepo.registry.presets": "Preset mirrors",
        "pnpmRepo.registry.custom": "Custom URL",
        "pnpmRepo.registry.apply": "Apply",
        "pnpmRepo.registry.confirmApply": "Switch the pnpm registry?",

        "pnpmRepo.msg.saved": "Saved",
        "pnpmRepo.msg.invalidURL": "URL must start with http:// or https://",

        "pnpmRepo.pkg.title": "Global Packages",
        "pnpmRepo.pkg.search": "Search packages",
        "pnpmRepo.pkg.total": "%d total",
        "pnpmRepo.pkg.uninstall": "Uninstall",
        "pnpmRepo.pkg.confirmDelete": "Uninstall this global pnpm package?",
        "pnpmRepo.pkg.empty": "No global pnpm packages installed",

        "pnpmRepo.store.title": "Store",
        "pnpmRepo.store.path": "Store directory",
        "pnpmRepo.store.size": "Store size",
        "pnpmRepo.store.prune": "Prune store",
        "pnpmRepo.store.pruned": "Store pruned",
        "pnpmRepo.store.confirmPrune": "Prune the pnpm store?",

        "pnpmRepo.missing.title": "pnpm Not Found",
        "pnpmRepo.missing.subtitle": "The `pnpm` command is not on PATH. Install it with `brew install pnpm` and try again.",

        "notify.pnpm.store.title": "pnpm store pruned",
        "notify.pnpm.store.body": "The local pnpm store has been fully released."
    ]
}
