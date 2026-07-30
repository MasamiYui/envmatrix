import XCTest
@testable import EnvMatrix

final class LocalizationSymmetryTests: XCTestCase {
    func testEnAndZhTablesShareAllKeys() {
        guard let en = L10n.strings["en"], let zh = L10n.strings["zh"] else {
            XCTFail("Missing en/zh tables")
            return
        }
        let enKeys = Set(en.keys)
        let zhKeys = Set(zh.keys)
        let missingInZh = enKeys.subtracting(zhKeys)
        let missingInEn = zhKeys.subtracting(enKeys)
        XCTAssertTrue(missingInZh.isEmpty, "Keys missing in zh: \(missingInZh.sorted())")
        XCTAssertTrue(missingInEn.isEmpty, "Keys missing in en: \(missingInEn.sorted())")
    }

    func testUvKeySymmetry() {
        let uvKeysEn = Set(L10n.strings["en"]?.keys.filter { $0.hasPrefix("uvRepo.") } ?? [])
        let uvKeysZh = Set(L10n.strings["zh"]?.keys.filter { $0.hasPrefix("uvRepo.") } ?? [])
        XCTAssertEqual(uvKeysEn, uvKeysZh)
        XCTAssertFalse(uvKeysEn.isEmpty)
    }

    func testPnpmKeySymmetry() {
        let pnpmKeysEn = Set(L10n.strings["en"]?.keys.filter { $0.hasPrefix("pnpmRepo.") } ?? [])
        let pnpmKeysZh = Set(L10n.strings["zh"]?.keys.filter { $0.hasPrefix("pnpmRepo.") } ?? [])
        XCTAssertEqual(pnpmKeysEn, pnpmKeysZh)
        XCTAssertFalse(pnpmKeysEn.isEmpty)
    }

    func testNavigationKeysForNewFeaturesExist() {
        for key in ["nav.uvRepo", "nav.pnpmRepo"] {
            XCTAssertNotNil(L10n.strings["en"]?[key], "en missing \(key)")
            XCTAssertNotNil(L10n.strings["zh"]?[key], "zh missing \(key)")
        }
    }
}
