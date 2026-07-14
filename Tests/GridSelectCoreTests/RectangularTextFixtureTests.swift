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

    func testFixtureRootTraversalStopsAtFilesystemRoot() {
        let fixtureRoot = RectangularTextFixtureLoader.resolveFixtureRoot(
            startingAt: [URL(fileURLWithPath: "/", isDirectory: true)]
        )

        XCTAssertNil(fixtureRoot)
    }

    func testFixtureRootResolutionFallsBackToLaterCandidate() throws {
        let expectedRoot = try RectangularTextFixtureLoader.resolveDefaultFixtureRoot()
        let fixtureRoot = RectangularTextFixtureLoader.resolveFixtureRoot(
            startingAt: [
                URL(fileURLWithPath: "/", isDirectory: true),
                expectedRoot,
            ]
        )

        XCTAssertEqual(fixtureRoot?.standardizedFileURL, expectedRoot.standardizedFileURL)
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
                    row.utf8.allSatisfy(isPrintableASCIIMonospaceByte),
                    "Fixture \(fixture.id) must use printable ASCII monospace bytes"
                )
                XCTAssertEqual(
                    row.utf8.count,
                    fixture.columnRange.count,
                    "Fixture \(fixture.id) does not preserve its rectangular width"
                )
            }
        }
    }

    func testPrintableASCIIMonospaceByteValidationRejectsUnsupportedContent() {
        for text in [" ", "~", "printable"] {
            XCTAssertTrue(text.utf8.allSatisfy(isPrintableASCIIMonospaceByte))
        }

        for text in ["\t", "\n", "\u{001F}", "\u{007F}", "é"] {
            XCTAssertFalse(text.utf8.allSatisfy(isPrintableASCIIMonospaceByte))
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

    func testMapsEveryDiscoveredFixtureThroughCoordinateGridContract() throws {
        let mapper = CoordinateGridMapper()
        let display = DisplayGeometry(
            displayID: 1,
            appKitFrame: ScreenRectangle(x: 0, y: 0, width: 2_000, height: 2_000),
            coreGraphicsBounds: ScreenRectangle(x: 0, y: 0, width: 2_000, height: 2_000),
            backingScale: 2
        )
        let originX = 100.0
        let originY = 50.0
        let characterWidth = 10.0
        let lineHeight = 20.0

        for fixture in try RectangularTextFixtureLoader.loadAll() {
            let canonicalY = originY + (Double(fixture.rowRange.lowerBound) * lineHeight)
            let selectionHeight = Double(fixture.rowRange.count) * lineHeight
            let selection = SelectionRectangle(
                displayID: 1,
                x: originX + (Double(fixture.columnRange.lowerBound) * characterWidth),
                y: 2_000 - (canonicalY + selectionHeight),
                width: Double(fixture.columnRange.count) * characterWidth,
                height: selectionHeight
            )
            let result = mapper.map(
                selection: selection,
                display: display,
                grid: TextGridGeometry(
                    originX: originX,
                    originY: originY,
                    characterWidth: characterWidth,
                    lineHeight: lineHeight
                ),
                visualLines: fixture.inputRows.map { VisualLine(text: $0) }
            )

            guard case let .selection(mapped) = result else {
                XCTFail("Fixture \(fixture.id) did not produce a grid selection: \(result)")
                continue
            }
            XCTAssertEqual(mapped.rowRange, fixture.rowRange, "Fixture \(fixture.id)")
            XCTAssertEqual(mapped.columnRange, fixture.columnRange, "Fixture \(fixture.id)")
            XCTAssertEqual(mapped.plainText, fixture.expectedPlainTextOutput, "Fixture \(fixture.id)")
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

private func isPrintableASCIIMonospaceByte(_ byte: UInt8) -> Bool {
    byte >= 0x20 && byte <= 0x7E
}
