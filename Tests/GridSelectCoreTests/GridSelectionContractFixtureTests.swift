import Foundation
import GridSelectCore
import XCTest

final class GridSelectionContractFixtureTests: XCTestCase {
    func testResolvesCanonicalLowercaseFixtureRoot() throws {
        let fixtureRoot = try GridSelectionContractFixtureLoader.resolveDefaultFixtureRoot()
        let expectedSuffix = ["tests", "fixtures", "grid-selection-contract"]
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
        let fixtureRoot = GridSelectionContractFixtureLoader.resolveFixtureRoot(
            startingAt: [URL(fileURLWithPath: "/", isDirectory: true)]
        )

        XCTAssertNil(fixtureRoot)
    }

    func testDiscoversUniqueFixturesCoveringEveryIssueRequirement() throws {
        let fixtures = try GridSelectionContractFixtureLoader.loadAll()
        let actualCoverage = Set(fixtures.flatMap(\.metadata.covers))

        XCTAssertFalse(fixtures.isEmpty)
        XCTAssertEqual(Set(fixtures.map(\.id)).count, fixtures.count)
        XCTAssertEqual(actualCoverage, Set(GridSelectionContractFixture.Coverage.allCases))
        for fixture in fixtures {
            XCTAssertFalse(fixture.metadata.description.isEmpty, "Fixture \(fixture.id)")
            XCTAssertFalse(fixture.metadata.covers.isEmpty, "Fixture \(fixture.id)")
        }
    }

    func testEveryFixtureMatchesEveryLifecycleCheckpoint() throws {
        for fixture in try GridSelectionContractFixtureLoader.loadAll() {
            let result = try GridSelectionContractHarness.run(fixture)
            let expectations = [fixture.metadata.expectedInitial]
                + fixture.metadata.steps.map(\.expected)

            XCTAssertEqual(result.snapshots.count, expectations.count, "Fixture \(fixture.id)")
            for (index, pair) in zip(result.snapshots, expectations).enumerated() {
                assert(
                    pair.0,
                    matches: pair.1,
                    fixtureID: fixture.id,
                    checkpoint: index
                )
            }
        }
    }

    func testKeyboardAndMouseEquivalenceGroupsReachTheSameSelection() throws {
        let fixtures = try GridSelectionContractFixtureLoader.loadAll()
        let grouped = Dictionary(grouping: fixtures.compactMap { fixture in
            fixture.metadata.equivalenceGroup.map { ($0, fixture) }
        }, by: { $0.0 })

        XCTAssertFalse(grouped.isEmpty)
        for (group, entries) in grouped {
            let members = entries.map { $0.1 }
            XCTAssertEqual(
                Set(members.map(\.metadata.start.method)),
                Set([.keyboard, .mouse]),
                "Equivalence group \(group)"
            )
            let results = try members.map { try GridSelectionContractHarness.run($0) }
            let reference = results[0].finalSnapshot
            for result in results.dropFirst() {
                XCTAssertEqual(result.finalSnapshot, reference, "Equivalence group \(group)")
            }
        }
    }

    func testHalfOpenOutputFixturesSliceOnlyTheFinalContractRange() throws {
        let fixtures = try GridSelectionContractFixtureLoader.loadAll().filter {
            $0.metadata.output != nil
        }

        XCTAssertFalse(fixtures.isEmpty)
        for fixture in fixtures {
            let output = try XCTUnwrap(fixture.metadata.output)
            let result = try GridSelectionContractHarness.run(fixture)

            XCTAssertEqual(
                result.plainTextOutput,
                output.expectedPlainText,
                "Fixture \(fixture.id)"
            )
            XCTAssertEqual(
                result.finalSnapshot.selection.rowRange,
                fixture.finalExpectation.rowRange.range,
                "Fixture \(fixture.id)"
            )
            XCTAssertEqual(
                result.finalSnapshot.selection.columnRange,
                fixture.finalExpectation.columnRange.range,
                "Fixture \(fixture.id)"
            )
        }
    }

    func testRejectsSymlinkedFixturePath() throws {
        try withTemporaryFixtureRoot { root, base in
            let target = base.appendingPathComponent("linked-fixture.json")
            try write(validFixtureJSON(id: "linked-fixture"), to: target)
            try FileManager.default.createSymbolicLink(
                at: root.appendingPathComponent("linked-fixture.json"),
                withDestinationURL: target
            )

            assertLoadingFails(from: root, containing: "regular non-symlink file")
        }
    }

    func testRejectsUnexpectedFixtureExtension() throws {
        try withTemporaryFixtureRoot { root, _ in
            try write("not a fixture", to: root.appendingPathComponent("notes.txt"))

            assertLoadingFails(from: root, containing: "lowercase .json extension")
        }
    }

    func testRejectsUnsafeAndMismatchedFixtureIDs() throws {
        try withTemporaryFixtureRoot { root, _ in
            try write(
                validFixtureJSON(id: "../unsafe"),
                to: root.appendingPathComponent("safe-name.json")
            )

            assertLoadingFails(from: root, containing: "lowercase kebab-case")
        }

        try withTemporaryFixtureRoot { root, _ in
            try write(
                validFixtureJSON(id: "metadata-name"),
                to: root.appendingPathComponent("file-name.json")
            )

            assertLoadingFails(from: root, containing: "does not match metadata id")
        }
    }

    func testRejectsUnsupportedSchemaAndInvalidActionParameters() throws {
        try withTemporaryFixtureRoot { root, _ in
            try write(
                validFixtureJSON(id: "unsupported-schema", schemaVersion: 2),
                to: root.appendingPathComponent("unsupported-schema.json")
            )

            assertLoadingFails(from: root, containing: "unsupported schema version 2")
        }

        try withTemporaryFixtureRoot { root, _ in
            try write(
                validFixtureJSON(id: "missing-direction", includeDirection: false),
                to: root.appendingPathComponent("missing-direction.json")
            )

            assertLoadingFails(from: root, containing: "invalid keyboard-move parameters")
        }
    }

    func testRejectsUnknownStepActionKeys() throws {
        try withTemporaryFixtureRoot { root, _ in
            try write(
                validFixtureJSON(
                    id: "unknown-action-key",
                    additionalActionField: #""repeet": 4,"#
                ),
                to: root.appendingPathComponent("unknown-action-key.json")
            )

            assertLoadingFails(from: root, containing: "unknown keys: repeet")
        }
    }

    func testRejectsExpectedRangesThatDisagreeWithAnchorAndFocus() throws {
        try withTemporaryFixtureRoot { root, _ in
            try write(
                validFixtureJSON(id: "wrong-range", finalColumnEnd: 2),
                to: root.appendingPathComponent("wrong-range.json")
            )

            assertLoadingFails(from: root, containing: "ranges do not match anchor and focus")
        }
    }

    private func assert(
        _ snapshot: GridSelectionContractHarness.Snapshot,
        matches expectation: GridSelectionContractFixture.ExpectedSelection,
        fixtureID: String,
        checkpoint: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let message = "Fixture \(fixtureID), checkpoint \(checkpoint)"
        XCTAssertEqual(snapshot.phase, expectation.phase, message, file: file, line: line)
        XCTAssertEqual(
            snapshot.selection.anchor,
            expectation.anchor.gridBoundary,
            message,
            file: file,
            line: line
        )
        XCTAssertEqual(
            snapshot.selection.focus,
            expectation.focus.gridBoundary,
            message,
            file: file,
            line: line
        )
        XCTAssertEqual(
            snapshot.selection.rowRange,
            expectation.rowRange.range,
            message,
            file: file,
            line: line
        )
        XCTAssertEqual(
            snapshot.selection.columnRange,
            expectation.columnRange.range,
            message,
            file: file,
            line: line
        )
        XCTAssertEqual(
            snapshot.selection.isEmpty,
            expectation.isEmpty,
            message,
            file: file,
            line: line
        )
    }

    private func assertLoadingFails(
        from root: URL,
        containing expectedMessage: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try GridSelectionContractFixtureLoader.loadAll(from: root),
            file: file,
            line: line
        ) { error in
            XCTAssertTrue(
                error.localizedDescription.contains(expectedMessage),
                "Expected \(error.localizedDescription) to contain \(expectedMessage)",
                file: file,
                line: line
            )
        }
    }

    private func withTemporaryFixtureRoot(
        _ body: (URL, URL) throws -> Void
    ) throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(
            "GridSelectionContractFixtureTests-\(UUID().uuidString)",
            isDirectory: true
        )
        let root = base.appendingPathComponent("fixtures", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: base)
        }
        try body(root, base)
    }

    private func write(_ contents: String, to url: URL) throws {
        try Data(contents.utf8).write(to: url, options: .atomic)
    }

    private func validFixtureJSON(
        id: String,
        schemaVersion: Int = 1,
        includeDirection: Bool = true,
        finalColumnEnd: Int = 1,
        additionalActionField: String = ""
    ) -> String {
        let direction = includeDirection ? #""direction": "right","# : ""
        return """
        {
          "schemaVersion": \(schemaVersion),
          "id": "\(id)",
          "description": "Temporary validation fixture.",
          "covers": [
            "one-character-horizontal-move"
          ],
          "start": {
            "method": "keyboard",
            "anchor": {
              "row": 0,
              "column": 0
            }
          },
          "expectedInitial": {
            "phase": "adjusting",
            "anchor": {
              "row": 0,
              "column": 0
            },
            "focus": {
              "row": 0,
              "column": 0
            },
            "rowRange": {
              "start": 0,
              "end": 1
            },
            "columnRange": {
              "start": 0,
              "end": 0
            },
            "isEmpty": true
          },
          "steps": [
            {
              "action": "keyboard-move",
              \(direction)
              \(additionalActionField)
              "expected": {
                "phase": "adjusting",
                "anchor": {
                  "row": 0,
                  "column": 0
                },
                "focus": {
                  "row": 0,
                  "column": 1
                },
                "rowRange": {
                  "start": 0,
                  "end": 1
                },
                "columnRange": {
                  "start": 0,
                  "end": \(finalColumnEnd)
                },
                "isEmpty": false
              }
            }
          ]
        }
        """
    }
}
