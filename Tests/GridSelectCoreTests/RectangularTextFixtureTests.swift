import Foundation
import GridSelectCore
import XCTest

final class RectangularTextFixtureTests: XCTestCase {
    private let formatter = ClipboardTextFormatter()

    func testResolvesCanonicalLowercaseFixtureRoot() throws {
        let fixtureRoot = try RectangularTextFixtureLoader.resolveDefaultFixtureRoot()
        let expectedSuffix = ["tests", "fixtures", "rectangular-text"]
        let actualSuffix = Array(fixtureRoot.pathComponents.suffix(expectedSuffix.count))
        var isDirectory: ObjCBool = false

        XCTAssertEqual(actualSuffix, expectedSuffix)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: fixtureRoot.path,
                isDirectory: &isDirectory
            )
        )
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testDiscoversValidFixturesWithoutPerFixtureRegistration() throws {
        let fixtures = try RectangularTextFixtureLoader.loadAll()

        XCTAssertFalse(fixtures.isEmpty)
        XCTAssertEqual(Set(fixtures.map(\.id)).count, fixtures.count)

        for fixture in fixtures {
            XCTAssertFalse(fixture.metadata.category.isEmpty, "Fixture \(fixture.id)")
            XCTAssertFalse(fixture.metadata.description.isEmpty, "Fixture \(fixture.id)")
            XCTAssertFalse(fixture.metadata.manualTargets.isEmpty, "Fixture \(fixture.id)")
        }
    }

    func testExpectedOutputPreservesRectangularShape() throws {
        for fixture in try RectangularTextFixtureLoader.loadAll() {
            let expectedRows = fixture.expectedPlainTextOutput
                .split(separator: "\n", omittingEmptySubsequences: false)

            XCTAssertEqual(
                expectedRows.count,
                fixture.rowRange.count,
                "Fixture \(fixture.id) has an unexpected output row count"
            )

            for row in expectedRows {
                XCTAssertTrue(
                    row.utf8.allSatisfy { $0 < 0x80 },
                    "Fixture \(fixture.id) must stay within the ASCII monospace MVP"
                )
                XCTAssertEqual(
                    row.utf8.count,
                    fixture.columnRange.count,
                    "Fixture \(fixture.id) does not preserve its rectangular width"
                )
            }
        }
    }

    func testFormatsEveryDiscoveredFixture() throws {
        for fixture in try RectangularTextFixtureLoader.loadAll() {
            let result = formatter.format(
                text: fixture.inputText,
                rows: fixture.rowRange,
                columns: fixture.columnRange
            )

            XCTAssertEqual(
                result.plainText,
                fixture.expectedPlainTextOutput,
                "Fixture \(fixture.id)"
            )
        }
    }

    func testSlicesFullyBackedFixturesWithTheCurrentPureGridContract() throws {
        let fixtures = try RectangularTextFixtureLoader.loadAll()
            .filter(\.hasFullyBackedSelection)

        XCTAssertFalse(fixtures.isEmpty)

        for fixture in fixtures {
            let result = TextGrid(rows: fixture.inputRows).slice(
                rows: fixture.rowRange,
                columns: fixture.columnRange
            )

            XCTAssertEqual(result, fixture.expectedPlainTextOutput, "Fixture \(fixture.id)")
        }
    }
}
