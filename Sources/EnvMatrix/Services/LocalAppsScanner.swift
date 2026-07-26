import Foundation

public protocol BrewCaskProbe {
    func caskTokenMap() async -> [String: String]
}

public final class DefaultBrewCaskProbe: BrewCaskProbe {
    private let brewPath: String

    public init(explicitPath: String? = nil) {
        if let p = explicitPath, FileManager.default.isExecutableFile(atPath: p) {
            self.brewPath = p
            return
        }
        let candidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        self.brewPath = candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? ""
    }

    public func caskTokenMap() async -> [String: String] {
        guard !brewPath.isEmpty else { return [:] }
        guard let listOut = Self.runSync(brewPath, ["list", "--cask", "-1"]) else { return [:] }
        let tokens = listOut
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var map: [String: String] = [:]
        for token in tokens {
            guard let out = Self.runSync(brewPath, ["list", "--cask", token]) else { continue }
            for line in out.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasSuffix(".app") else { continue }
                let base = (trimmed as NSString).lastPathComponent.lowercased()
                if !base.isEmpty { map[base] = token }
            }
        }
        return map
    }

    private static func runSync(_ launchPath: String, _ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        process.environment = [
            "HOME": NSHomeDirectory(),
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin",
            "HOMEBREW_NO_AUTO_UPDATE": "1",
            "HOMEBREW_NO_ENV_HINTS": "1",
            "HOMEBREW_NO_ANALYTICS": "1"
        ]
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        _ = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if process.terminationStatus != 0 { return nil }
        return String(data: data, encoding: .utf8)
    }
}

public protocol LocalAppsScanner {
    func scan(roots: [URL]) async throws -> [LocalApp]
}

public final class DefaultLocalAppsScanner: LocalAppsScanner {
    private let probe: BrewCaskProbe

    public init(probe: BrewCaskProbe) {
        self.probe = probe
    }

    public func scan(roots: [URL]) async throws -> [LocalApp] {
        let bundles = collectBundles(roots: roots)
        if bundles.isEmpty { return [] }
        let caskMap = await probe.caskTokenMap()

        var results: [LocalApp] = []
        results.reserveCapacity(bundles.count)
        await withTaskGroup(of: LocalApp?.self) { group in
            for url in bundles {
                group.addTask {
                    Self.parseBundle(url, caskMap: caskMap)
                }
            }
            for await value in group {
                if let app = value { results.append(app) }
            }
        }
        return results
    }

    private func collectBundles(roots: [URL]) -> [URL] {
        let fm = FileManager.default
        var seen = Set<String>()
        var out: [URL] = []
        for root in roots {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let items: [URL]
            do {
                items = try fm.contentsOfDirectory(
                    at: root,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )
            } catch {
                continue
            }
            for item in items {
                let isAppDir = Self.isAppBundle(item, fm: fm)
                if isAppDir {
                    let path = item.standardizedFileURL.path
                    if seen.insert(path).inserted { out.append(item) }
                    continue
                }
                var subIsDir: ObjCBool = false
                guard fm.fileExists(atPath: item.path, isDirectory: &subIsDir), subIsDir.boolValue else { continue }
                let subItems: [URL]
                do {
                    subItems = try fm.contentsOfDirectory(
                        at: item,
                        includingPropertiesForKeys: [.isDirectoryKey],
                        options: [.skipsHiddenFiles]
                    )
                } catch {
                    continue
                }
                for sub in subItems where Self.isAppBundle(sub, fm: fm) {
                    let path = sub.standardizedFileURL.path
                    if seen.insert(path).inserted { out.append(sub) }
                }
            }
        }
        return out
    }

    private static func isAppBundle(_ url: URL, fm: FileManager) -> Bool {
        guard url.pathExtension.lowercased() == "app" else { return false }
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    private static func parseBundle(_ url: URL, caskMap: [String: String]) -> LocalApp? {
        let fm = FileManager.default
        let contents = url.appendingPathComponent("Contents", isDirectory: true)
        let plistURL = contents.appendingPathComponent("Info.plist")

        guard let plistData = try? Data(contentsOf: plistURL) else { return nil }
        var format = PropertyListSerialization.PropertyListFormat.binary
        let plistObject: Any
        do {
            plistObject = try PropertyListSerialization.propertyList(
                from: plistData,
                options: [],
                format: &format
            )
        } catch {
            return nil
        }
        let plist = plistObject as? [String: Any] ?? [:]

        let fileName = url.deletingPathExtension().lastPathComponent
        let displayName = (plist["CFBundleDisplayName"] as? String)?.nonEmpty
            ?? (plist["CFBundleName"] as? String)?.nonEmpty
            ?? fileName
        let name = (plist["CFBundleName"] as? String)?.nonEmpty ?? fileName
        let shortVersion = (plist["CFBundleShortVersionString"] as? String)?.nonEmpty
        let bundleVersion = (plist["CFBundleVersion"] as? String)?.nonEmpty
        let version = shortVersion ?? bundleVersion ?? ""
        let bundleId = (plist["CFBundleIdentifier"] as? String) ?? ""

        let sizeBytes = computeBundleSize(url: url)

        let source: LocalAppSource
        let receipt = contents.appendingPathComponent("_MASReceipt").appendingPathComponent("receipt")
        if fm.fileExists(atPath: receipt.path) {
            source = .appStore
        } else {
            let key = url.lastPathComponent.lowercased()
            if let token = caskMap[key] {
                source = .brewCask(token: token)
            } else {
                source = .other
            }
        }

        let path = url.standardizedFileURL.path
        let isProtected = path.hasPrefix("/System/Applications/") || bundleId.hasPrefix("com.apple.")

        let iconPath = resolveIconPath(
            plist: plist,
            resourcesDir: contents.appendingPathComponent("Resources", isDirectory: true),
            fm: fm
        )

        return LocalApp(
            name: name,
            displayName: displayName,
            version: version,
            bundleId: bundleId,
            bundlePath: url,
            sizeBytes: sizeBytes,
            source: source,
            isProtected: isProtected,
            iconPath: iconPath
        )
    }

    private static func computeBundleSize(url: URL) -> Int64 {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: Set(keys))
            guard let values, values.isRegularFile == true else { continue }
            if let size = values.totalFileAllocatedSize {
                total &+= Int64(size)
            }
        }
        return total
    }

    private static func resolveIconPath(
        plist: [String: Any],
        resourcesDir: URL,
        fm: FileManager
    ) -> URL? {
        guard let raw = (plist["CFBundleIconFile"] as? String)?.nonEmpty else { return nil }
        let fileName = raw.hasSuffix(".icns") ? raw : raw + ".icns"
        let candidate = resourcesDir.appendingPathComponent(fileName)
        guard fm.fileExists(atPath: candidate.path) else { return nil }
        return candidate
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
