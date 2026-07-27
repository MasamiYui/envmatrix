import XCTest
@testable import EnvMatrix

// Tests ensuring container-related localization keys are present and consistent across en/zh.
final class ContainerContextsLocalizationTests: XCTestCase {
    private func isContainerKey(_ key: String) -> Bool {
        key.hasPrefix("container.") || key == "nav.containerContexts"
    }

    private func containerKeys(_ dict: [String: String]) -> Set<String> {
        Set(dict.keys.filter(isContainerKey))
    }

    func test_containerKeys_matchBetweenEnAndZh() {
        let en = L10n.strings["en"] ?? [:]
        let zh = L10n.strings["zh"] ?? [:]
        let enKeys = containerKeys(en)
        let zhKeys = containerKeys(zh)
        XCTAssertEqual(enKeys, zhKeys)
        XCTAssertFalse(enKeys.isEmpty, "Expected container keys to exist")
    }

    func test_containerValues_areNonEmpty() {
        let en = L10n.strings["en"] ?? [:]
        let zh = L10n.strings["zh"] ?? [:]
        for (key, value) in en where isContainerKey(key) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertGreaterThan(trimmed.count, 0, "en value empty for key=\(key)")
        }
        for (key, value) in zh where isContainerKey(key) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertGreaterThan(trimmed.count, 0, "zh value empty for key=\(key)")
        }
    }

    func test_everyEnKeyHasZhCounterpartAndViceVersa() {
        let en = L10n.strings["en"] ?? [:]
        let zh = L10n.strings["zh"] ?? [:]
        let enKeys = containerKeys(en)
        let zhKeys = containerKeys(zh)
        for key in enKeys {
            XCTAssertNotNil(zh[key], "Missing zh translation for \(key)")
        }
        for key in zhKeys {
            XCTAssertNotNil(en[key], "Missing en translation for \(key)")
        }
    }
}
