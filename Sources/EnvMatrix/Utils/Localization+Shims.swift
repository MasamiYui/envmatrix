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
        "shims.banner.reveal": "Reveal"
    ]

    static let zhShims: [String: String] = [
        "shims.banner.title": "终端暂时还看不到你切换的版本",
        "shims.banner.body": "“设为活动”只是把 ~/.envmatrix/shims 指向所选版本，但该目录不在你的 shell PATH 中。把下面这行加入 %@（写入前会自动备份），然后新开一个终端窗口。",
        "shims.banner.copy": "复制",
        "shims.banner.copied": "已复制",
        "shims.banner.addToRc": "写入 %@",
        "shims.banner.done.title": "已把 PATH 配置写入 %@",
        "shims.banner.done.body": "新开一个终端窗口（或对该文件执行 source）后生效。原文件已备份为 .envmatrix.bak。",
        "shims.banner.reveal": "在访达中显示"
    ]
}
