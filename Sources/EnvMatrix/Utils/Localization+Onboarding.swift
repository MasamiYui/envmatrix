import Foundation

extension L10n {
    static let enOnboarding: [String: String] = [
        "onboarding.step": "Step %d of %d",
        "onboarding.skip": "Skip",
        "onboarding.back": "Back",
        "onboarding.next": "Continue",
        "onboarding.finish": "Get Started",
        "onboarding.welcome.title": "Welcome to EnvMatrix",
        "onboarding.welcome.subtitle": "One place for runtimes, package mirrors, caches, hosts and AI tooling on this Mac.",
        "onboarding.welcome.scanning": "Scanning your shell PATH for runtimes…",
        "onboarding.welcome.found": "%d runtimes detected",
        "onboarding.welcome.body": "Nothing has been changed yet. Every write EnvMatrix makes is backed up first and listed in Settings › History, where it can be rolled back.",
        "onboarding.path.title": "Let the terminal see your switches",
        "onboarding.path.subtitle": "EnvMatrix switches runtimes by pointing ~/.envmatrix/shims at the chosen version.",
        "onboarding.path.checking": "Checking your shell PATH…",
        "onboarding.path.configured": "The shims directory is already on PATH.",
        "onboarding.path.missing": "The shims directory is not on PATH yet.",
        "onboarding.path.body": "You can do this later from the banner on any runtime page or from the Dashboard's \"Needs attention\" list.",
        "onboarding.mirrors.title": "Mirrors and preferences",
        "onboarding.mirrors.subtitle": "Registries default to their official sources. If you are in mainland China, one click switches all of them to fast mirrors.",
        "onboarding.mirrors.keepOfficial": "Or keep official sources — you can change this any time in Settings.",
        "onboarding.mirrors.body": "Use ⌘F to search across every package manager, ⌘R to refresh the current page, and ⌘, for Settings.",
        "settings.showOnboarding": "Show the welcome guide again"
    ]

    static let zhOnboarding: [String: String] = [
        "onboarding.step": "第 %d 步，共 %d 步",
        "onboarding.skip": "跳过",
        "onboarding.back": "上一步",
        "onboarding.next": "继续",
        "onboarding.finish": "开始使用",
        "onboarding.welcome.title": "欢迎使用 EnvMatrix",
        "onboarding.welcome.subtitle": "在一个界面里管理这台 Mac 上的运行时、包镜像、缓存、hosts 与 AI 工具。",
        "onboarding.welcome.scanning": "正在扫描 shell PATH 中的运行时…",
        "onboarding.welcome.found": "检测到 %d 个运行时",
        "onboarding.welcome.body": "目前还没有做任何修改。EnvMatrix 的每一次写入都会先备份，并记录在 设置 › 历史 中，随时可以回滚。",
        "onboarding.path.title": "让终端看到你的切换",
        "onboarding.path.subtitle": "EnvMatrix 通过把 ~/.envmatrix/shims 指向所选版本来切换运行时。",
        "onboarding.path.checking": "正在检查 shell PATH…",
        "onboarding.path.configured": "shims 目录已经在 PATH 中。",
        "onboarding.path.missing": "shims 目录还不在 PATH 中。",
        "onboarding.path.body": "以后也可以在任意运行时页面顶部的提示条，或仪表盘的“需要关注”列表中完成这一步。",
        "onboarding.mirrors.title": "镜像与偏好",
        "onboarding.mirrors.subtitle": "各包管理源默认为官方源。如果你在中国大陆，一键即可全部切换到高速镜像。",
        "onboarding.mirrors.keepOfficial": "也可以保持官方源，之后随时在设置中更改。",
        "onboarding.mirrors.body": "⌘F 跨所有包管理器搜索，⌘R 刷新当前页面，⌘, 打开设置。",
        "settings.showOnboarding": "再次显示欢迎引导"
    ]
}
