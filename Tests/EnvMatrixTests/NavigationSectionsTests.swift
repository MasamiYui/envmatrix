import XCTest
@testable import EnvMatrix

final class NavigationSectionsTests: XCTestCase {
    func testEverySectionHasAtLeastTwoItems() {
        for section in NavigationItem.allSections {
            XCTAssertGreaterThanOrEqual(section.items.count, 1, section.id)
        }
        // The old single-item "Project Environments" group is gone.
        XCTAssertFalse(NavigationItem.allSections.contains { $0.items == [.packagesProjectEnv] })
    }

    func testSectionsCoverEveryNavigationItemExactlyOnce() {
        let flattened = NavigationItem.allSections.flatMap { $0.items }
        XCTAssertEqual(Set(flattened).count, flattened.count, "duplicate sidebar entries")
        XCTAssertEqual(Set(flattened), Set(NavigationItem.allCases))
    }

    func testSectionIDsAreStableAndUnique() {
        let ids = NavigationItem.allSections.map { $0.id }
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(ids.contains(NavigationSection.devEnvironmentsID))
    }

    func testFilterMatchesAliasesAndIDs() {
        XCTAssertTrue(NavigationItem.packagesNode.matches("npm"))
        XCTAssertTrue(NavigationItem.packagesNode.matches("NPM"))
        XCTAssertTrue(NavigationItem.systemContainerContexts.matches("docker"))
        XCTAssertTrue(NavigationItem.devEnv(.python).matches("python3"))
        XCTAssertTrue(NavigationItem.settings.matches("settings"))
        XCTAssertFalse(NavigationItem.packagesBrew.matches("docker"))
    }

    func testPackageIconsAreDistinct() {
        let packageItems: [NavigationItem] = [
            .packagesBrew, .packagesMaven, .packagesGo, .packagesNode, .packagesPython,
            .packagesRuby, .packagesRust, .packagesPhp, .packagesDotnet, .packagesUv, .packagesPnpm
        ]
        let icons = packageItems.map { $0.systemImage }
        XCTAssertEqual(Set(icons).count, icons.count, "package managers must not share one icon")
    }
}
