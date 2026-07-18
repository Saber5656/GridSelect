import Foundation
import GridSelectCore

struct GridSelectionContractFixture {
    let metadata: Metadata

    var id: String {
        metadata.id
    }

    var finalExpectation: ExpectedSelection {
        metadata.steps.last?.expected ?? metadata.expectedInitial
    }

    struct Metadata: Decodable {
        let schemaVersion: Int
        let id: String
        let description: String
        let covers: [Coverage]
        let equivalenceGroup: String?
        let start: Start
        let expectedInitial: ExpectedSelection
        let steps: [Step]
        let output: OutputAssertion?
    }

    enum Coverage: String, CaseIterable, Decodable, Hashable {
        case zeroWidth = "zero-width"
        case oneCharacterHorizontalMove = "one-character-horizontal-move"
        case adjacentRowMultiCursorExpansion = "adjacent-row-multi-cursor-expansion"
        case anchorCrossing = "anchor-crossing"
        case keyRepeat = "key-repeat"
        case equivalentMouseDrag = "equivalent-mouse-drag"
        case halfOpenOutputRange = "half-open-output-range"
    }

    enum InputMethod: String, Decodable, Hashable {
        case keyboard
        case mouse
    }

    enum Phase: String, Decodable, Equatable {
        case adjusting
        case selected
    }

    enum Action: String, Decodable, Equatable {
        case keyboardMove = "keyboard-move"
        case mouseMove = "mouse-move"
        case freeze
    }

    enum Direction: String, Decodable, Equatable {
        case left
        case right
        case up
        case down

        var gridDirection: GridDirection {
            switch self {
            case .left:
                return .left
            case .right:
                return .right
            case .up:
                return .up
            case .down:
                return .down
            }
        }
    }

    struct Start: Decodable {
        let method: InputMethod
        let anchor: Boundary
    }

    struct Step: Decodable {
        let action: Action
        let direction: Direction?
        let boundary: Boundary?
        let repeatCount: Int?
        let expected: ExpectedSelection

        var effectiveRepeatCount: Int {
            repeatCount ?? 1
        }

        private enum CodingKeys: String, CodingKey {
            case action
            case direction
            case boundary
            case repeatCount = "repeat"
            case expected
        }
    }

    struct ExpectedSelection: Decodable {
        let phase: Phase
        let anchor: Boundary
        let focus: Boundary
        let rowRange: Bounds
        let columnRange: Bounds
        let isEmpty: Bool

        var selection: GridIndexSelection {
            GridIndexSelection(
                anchor: anchor.gridBoundary,
                focus: focus.gridBoundary
            )
        }
    }

    struct Boundary: Decodable, Equatable {
        let row: Int
        let column: Int

        var gridBoundary: GridBoundary {
            GridBoundary(row: row, column: column)
        }
    }

    struct Bounds: Decodable, Equatable {
        let start: Int
        let end: Int

        var range: Range<Int> {
            start..<end
        }

        var count: Int {
            end - start
        }
    }

    struct OutputAssertion: Decodable {
        let sourceRows: [String]
        let expectedPlainText: String
    }
}

enum GridSelectionContractFixtureLoader {
    private static let supportedSchemaVersion = 1
    private static let maximumRepeatCount = 64
    private static let readmeFileName = "README.md"
    private static let safeIDPattern = #"^[a-z0-9]+(?:-[a-z0-9]+)*$"#

    static func loadAll(from fixtureRoot: URL? = nil) throws -> [GridSelectionContractFixture] {
        let root = try validatedRoot(fixtureRoot ?? resolveDefaultFixtureRoot())
        let entries = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ],
            options: [.skipsHiddenFiles]
        )
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var fixtureURLs: [URL] = []
        for entry in entries {
            if entry.lastPathComponent == readmeFileName {
                continue
            }
            let values = try entry.resourceValues(
                forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
            )
            guard values.isSymbolicLink != true,
                  values.isDirectory != true,
                  values.isRegularFile == true
            else {
                throw LoadingError(
                    "Fixture entry \(entry.lastPathComponent) must be a regular non-symlink file"
                )
            }
            guard entry.pathExtension == "json" else {
                throw LoadingError(
                    "Fixture entry \(entry.lastPathComponent) must use the lowercase .json extension"
                )
            }
            fixtureURLs.append(entry)
        }

        guard !fixtureURLs.isEmpty else {
            throw LoadingError("No grid selection contract fixtures found at \(root.path)")
        }

        let fixtures = try fixtureURLs.map(loadFixture)
        guard Set(fixtures.map(\.id)).count == fixtures.count else {
            throw LoadingError("Grid selection contract fixture ids must be unique")
        }
        try validateEquivalenceGroups(fixtures)
        return fixtures
    }

    static func resolveDefaultFixtureRoot() throws -> URL {
        var startingURLs: [URL] = []
        let sourcePath = #filePath
        if sourcePath.hasPrefix("/") {
            startingURLs.append(
                URL(fileURLWithPath: sourcePath).deletingLastPathComponent()
            )
        }
        startingURLs.append(Bundle.main.bundleURL)
        if let executableURL = Bundle.main.executableURL {
            startingURLs.append(executableURL.deletingLastPathComponent())
        }

        if let root = resolveFixtureRoot(startingAt: startingURLs) {
            return root
        }
        throw LoadingError(
            "Could not locate tests/fixtures/grid-selection-contract "
                + "from the test source or executable"
        )
    }

    static func resolveFixtureRoot(startingAt startingURLs: [URL]) -> URL? {
        for startingURL in startingURLs {
            if let root = fixtureRoot(above: startingURL) {
                return root
            }
        }
        return nil
    }

    private static func validatedRoot(_ root: URL) throws -> URL {
        let standardizedRoot = root.standardizedFileURL
        let values: URLResourceValues
        do {
            values = try standardizedRoot.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )
        } catch {
            throw LoadingError("Fixture root does not exist at \(standardizedRoot.path)")
        }
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw LoadingError("Fixture root must be a non-symlink directory")
        }
        return standardizedRoot
    }

    private static func fixtureRoot(above startingURL: URL) -> URL? {
        var currentURL = startingURL.standardizedFileURL
        while true {
            let packageManifestURL = currentURL.appendingPathComponent("Package.swift")
            let fixtureRoot = currentURL
                .appendingPathComponent("tests", isDirectory: true)
                .appendingPathComponent("fixtures", isDirectory: true)
                .appendingPathComponent("grid-selection-contract", isDirectory: true)

            if FileManager.default.fileExists(atPath: packageManifestURL.path),
               FileManager.default.fileExists(atPath: fixtureRoot.path)
            {
                return fixtureRoot
            }

            guard currentURL.pathComponents.count > 1 else {
                return nil
            }
            let parentURL = currentURL
                .deletingLastPathComponent()
                .standardizedFileURL
            guard parentURL.pathComponents.count < currentURL.pathComponents.count else {
                return nil
            }
            currentURL = parentURL
        }
    }

    private static func loadFixture(from fixtureURL: URL) throws -> GridSelectionContractFixture {
        let fileName = fixtureURL.lastPathComponent
        let fileStem = fixtureURL.deletingPathExtension().lastPathComponent
        let metadata: GridSelectionContractFixture.Metadata
        do {
            let data = try Data(contentsOf: fixtureURL)
            try validateKnownStepKeys(in: data, fixtureName: fileName)
            metadata = try JSONDecoder().decode(
                GridSelectionContractFixture.Metadata.self,
                from: data
            )
        } catch {
            throw LoadingError("Fixture \(fileName) could not be decoded: \(error.localizedDescription)")
        }

        try validate(metadata, fileStem: fileStem)
        return GridSelectionContractFixture(metadata: metadata)
    }

    private static func validateKnownStepKeys(in data: Data, fixtureName: String) throws {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let root = json as? [String: Any],
              let steps = root["steps"] as? [Any]
        else {
            return
        }

        for (index, value) in steps.enumerated() {
            guard let step = value as? [String: Any] else {
                continue
            }
            try rejectUnknownKeys(
                in: step,
                allowed: ["action", "direction", "boundary", "repeat", "expected"],
                context: "steps[\(index)]",
                fixtureName: fixtureName
            )
        }
    }

    private static func rejectUnknownKeys(
        in object: [String: Any],
        allowed: Set<String>,
        context: String,
        fixtureName: String
    ) throws {
        let unknown = Set(object.keys).subtracting(allowed).sorted()
        guard unknown.isEmpty else {
            throw LoadingError(
                "Fixture \(fixtureName) \(context) contains unknown keys: "
                    + unknown.joined(separator: ", ")
            )
        }
    }

    private static func validate(
        _ metadata: GridSelectionContractFixture.Metadata,
        fileStem: String
    ) throws {
        let fixtureID = metadata.id
        guard metadata.schemaVersion == supportedSchemaVersion else {
            throw LoadingError(
                "Fixture \(fixtureID) uses unsupported schema version \(metadata.schemaVersion)"
            )
        }
        guard isSafeID(fixtureID) else {
            throw LoadingError("Fixture id \(fixtureID) must be lowercase kebab-case")
        }
        guard fixtureID == fileStem else {
            throw LoadingError(
                "Fixture file \(fileStem).json does not match metadata id \(fixtureID)"
            )
        }
        guard !metadata.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LoadingError("Fixture \(fixtureID) must have a description")
        }
        guard !metadata.covers.isEmpty,
              Set(metadata.covers).count == metadata.covers.count
        else {
            throw LoadingError("Fixture \(fixtureID) must have unique coverage tags")
        }
        if let group = metadata.equivalenceGroup, !isSafeID(group) {
            throw LoadingError(
                "Fixture \(fixtureID) equivalence group must be lowercase kebab-case"
            )
        }

        try validate(metadata.start.anchor, named: "start anchor", fixtureID: fixtureID)
        try validate(
            metadata.expectedInitial,
            immutableAnchor: metadata.start.anchor,
            named: "expectedInitial",
            fixtureID: fixtureID
        )
        guard metadata.expectedInitial.phase == .adjusting,
              metadata.expectedInitial.focus == metadata.start.anchor
        else {
            throw LoadingError(
                "Fixture \(fixtureID) initial expectation must be adjusting at the anchor"
            )
        }

        var didFreeze = false
        for (index, step) in metadata.steps.enumerated() {
            guard !didFreeze else {
                throw LoadingError("Fixture \(fixtureID) contains an action after freeze")
            }
            try validate(
                step,
                at: index,
                method: metadata.start.method,
                immutableAnchor: metadata.start.anchor,
                fixtureID: fixtureID
            )
            if step.action == .freeze {
                didFreeze = true
                guard index == metadata.steps.indices.last else {
                    throw LoadingError("Fixture \(fixtureID) freeze must be the last action")
                }
            }
        }

        if let output = metadata.output {
            try validate(
                output,
                selection: metadata.steps.last?.expected ?? metadata.expectedInitial,
                fixtureID: fixtureID
            )
        }
        try validateDeclaredCoverage(metadata, fixtureID: fixtureID)
    }

    private static func validate(
        _ step: GridSelectionContractFixture.Step,
        at index: Int,
        method: GridSelectionContractFixture.InputMethod,
        immutableAnchor: GridSelectionContractFixture.Boundary,
        fixtureID: String
    ) throws {
        let position = "step \(index + 1)"
        switch step.action {
        case .keyboardMove:
            guard method == .keyboard,
                  step.direction != nil,
                  step.boundary == nil,
                  (1...maximumRepeatCount).contains(step.effectiveRepeatCount)
            else {
                throw LoadingError(
                    "Fixture \(fixtureID) \(position) has invalid keyboard-move parameters"
                )
            }
            guard step.expected.phase == .adjusting else {
                throw LoadingError(
                    "Fixture \(fixtureID) \(position) keyboard move must remain adjusting"
                )
            }
        case .mouseMove:
            guard method == .mouse,
                  step.direction == nil,
                  let boundary = step.boundary,
                  step.repeatCount == nil
            else {
                throw LoadingError(
                    "Fixture \(fixtureID) \(position) has invalid mouse-move parameters"
                )
            }
            try validate(boundary, named: "\(position) boundary", fixtureID: fixtureID)
            guard step.expected.phase == .adjusting else {
                throw LoadingError(
                    "Fixture \(fixtureID) \(position) mouse move must remain adjusting"
                )
            }
        case .freeze:
            guard step.direction == nil,
                  step.boundary == nil,
                  step.repeatCount == nil,
                  step.expected.phase == .selected
            else {
                throw LoadingError(
                    "Fixture \(fixtureID) \(position) has invalid freeze parameters"
                )
            }
        }

        try validate(
            step.expected,
            immutableAnchor: immutableAnchor,
            named: position,
            fixtureID: fixtureID
        )
    }

    private static func validate(
        _ expectation: GridSelectionContractFixture.ExpectedSelection,
        immutableAnchor: GridSelectionContractFixture.Boundary,
        named name: String,
        fixtureID: String
    ) throws {
        try validate(expectation.anchor, named: "\(name) anchor", fixtureID: fixtureID)
        try validate(expectation.focus, named: "\(name) focus", fixtureID: fixtureID)
        try validate(
            expectation.rowRange,
            named: "\(name) rowRange",
            allowsEmpty: false,
            fixtureID: fixtureID
        )
        try validate(
            expectation.columnRange,
            named: "\(name) columnRange",
            allowsEmpty: true,
            fixtureID: fixtureID
        )
        guard expectation.anchor == immutableAnchor else {
            throw LoadingError("Fixture \(fixtureID) \(name) changes the immutable anchor")
        }

        let expectedRows = GridSelectionContractFixture.Bounds(
            start: min(expectation.anchor.row, expectation.focus.row),
            end: max(expectation.anchor.row, expectation.focus.row) + 1
        )
        let expectedColumns = GridSelectionContractFixture.Bounds(
            start: min(expectation.anchor.column, expectation.focus.column),
            end: max(expectation.anchor.column, expectation.focus.column)
        )
        guard expectation.rowRange == expectedRows,
              expectation.columnRange == expectedColumns,
              expectation.isEmpty == (expectedColumns.start == expectedColumns.end)
        else {
            throw LoadingError(
                "Fixture \(fixtureID) \(name) ranges do not match anchor and focus"
            )
        }
    }

    private static func validate(
        _ boundary: GridSelectionContractFixture.Boundary,
        named name: String,
        fixtureID: String
    ) throws {
        guard boundary.row >= 0,
              boundary.row < Int.max,
              boundary.column >= 0
        else {
            throw LoadingError("Fixture \(fixtureID) has invalid \(name)")
        }
    }

    private static func validate(
        _ bounds: GridSelectionContractFixture.Bounds,
        named name: String,
        allowsEmpty: Bool,
        fixtureID: String
    ) throws {
        let ordered = allowsEmpty ? bounds.start <= bounds.end : bounds.start < bounds.end
        guard bounds.start >= 0, ordered else {
            throw LoadingError(
                "Fixture \(fixtureID) has invalid \(name) [\(bounds.start), \(bounds.end))"
            )
        }
    }

    private static func validate(
        _ output: GridSelectionContractFixture.OutputAssertion,
        selection: GridSelectionContractFixture.ExpectedSelection,
        fixtureID: String
    ) throws {
        guard !output.sourceRows.isEmpty,
              !selection.columnRange.range.isEmpty,
              selection.rowRange.end <= output.sourceRows.count
        else {
            throw LoadingError("Fixture \(fixtureID) output does not fully back its final range")
        }
        let selectedRows = output.sourceRows[selection.rowRange.range]
        guard selectedRows.allSatisfy({ $0.count >= selection.columnRange.end }) else {
            throw LoadingError("Fixture \(fixtureID) output rows are shorter than its final range")
        }
        guard !output.expectedPlainText.contains("\r"),
              !output.expectedPlainText.hasSuffix("\n")
        else {
            throw LoadingError(
                "Fixture \(fixtureID) expected output must use LF without a final newline"
            )
        }
    }

    private static func validateDeclaredCoverage(
        _ metadata: GridSelectionContractFixture.Metadata,
        fixtureID: String
    ) throws {
        let expectations = [metadata.expectedInitial] + metadata.steps.map(\.expected)
        let final = metadata.steps.last?.expected ?? metadata.expectedInitial
        for coverage in metadata.covers {
            let isDemonstrated: Bool
            switch coverage {
            case .zeroWidth:
                isDemonstrated = final.isEmpty
            case .oneCharacterHorizontalMove:
                isDemonstrated = final.rowRange.count == 1
                    && final.columnRange.count == 1
                    && metadata.steps.contains {
                        $0.action == .keyboardMove
                            && ($0.direction == .left || $0.direction == .right)
                            && $0.effectiveRepeatCount == 1
                    }
            case .adjacentRowMultiCursorExpansion:
                isDemonstrated = final.rowRange.count == 2
                    && final.columnRange.count == 1
            case .anchorCrossing:
                let anchorColumn = metadata.start.anchor.column
                isDemonstrated = expectations.contains { $0.focus.column > anchorColumn }
                    && expectations.contains { $0.focus.column < anchorColumn }
            case .keyRepeat:
                isDemonstrated = metadata.steps.contains {
                    $0.action == .keyboardMove && $0.effectiveRepeatCount > 1
                }
            case .equivalentMouseDrag:
                isDemonstrated = metadata.equivalenceGroup != nil
            case .halfOpenOutputRange:
                isDemonstrated = metadata.output != nil
                    && !final.rowRange.range.isEmpty
                    && !final.columnRange.range.isEmpty
            }
            guard isDemonstrated else {
                throw LoadingError(
                    "Fixture \(fixtureID) does not demonstrate declared coverage \(coverage.rawValue)"
                )
            }
        }

        let declaresEquivalence = metadata.covers.contains(.equivalentMouseDrag)
        guard declaresEquivalence == (metadata.equivalenceGroup != nil) else {
            throw LoadingError(
                "Fixture \(fixtureID) equivalence group and coverage tag must appear together"
            )
        }
    }

    private static func validateEquivalenceGroups(
        _ fixtures: [GridSelectionContractFixture]
    ) throws {
        let grouped = Dictionary(grouping: fixtures.compactMap { fixture in
            fixture.metadata.equivalenceGroup.map { ($0, fixture) }
        }, by: { $0.0 })

        for (group, entries) in grouped {
            let members = entries.map { $0.1 }
            let methods = Set(members.map(\.metadata.start.method))
            guard methods == Set([.keyboard, .mouse]) else {
                throw LoadingError(
                    "Equivalence group \(group) must contain keyboard and mouse fixtures"
                )
            }

            guard let first = members.first?.finalExpectation else {
                continue
            }
            guard members.dropFirst().allSatisfy({ candidate in
                let expectation = candidate.finalExpectation
                return expectation.phase == first.phase
                    && expectation.rowRange == first.rowRange
                    && expectation.columnRange == first.columnRange
                    && expectation.isEmpty == first.isEmpty
            }) else {
                throw LoadingError(
                    "Equivalence group \(group) final selections do not match"
                )
            }
        }
    }

    private static func isSafeID(_ value: String) -> Bool {
        guard let match = value.range(of: safeIDPattern, options: .regularExpression) else {
            return false
        }
        return match == value.startIndex..<value.endIndex
    }

    struct LoadingError: LocalizedError {
        let message: String

        init(_ message: String) {
            self.message = message
        }

        var errorDescription: String? {
            message
        }
    }
}
