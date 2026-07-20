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
}
