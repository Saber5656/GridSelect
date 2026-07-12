import Foundation

struct RectangularTextFixture {
    let metadata: Metadata
    let inputText: String
    let expectedPlainTextOutput: String

    var id: String {
        metadata.id
    }

    var rowRange: Range<Int> {
        metadata.selection.rows.start..<metadata.selection.rows.end
    }

    var columnRange: Range<Int> {
        metadata.selection.columns.start..<metadata.selection.columns.end
    }

    var inputRows: [String] {
        inputText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }

    var hasFullyBackedSelection: Bool {
        rowRange.upperBound <= inputRows.count
            && inputRows[rowRange].allSatisfy { $0.utf8.count >= columnRange.upperBound }
    }

    struct Metadata: Decodable {
        let schemaVersion: Int
        let id: String
        let category: String
        let description: String
        let input: String
        let expectedPlainTextOutput: String
        let selection: Selection
        let manualTargets: [String]
        let notes: [String]
    }

    struct Selection: Decodable {
        let indexing: String
        let rows: Bounds
        let columns: Bounds
    }

    struct Bounds: Decodable {
        let start: Int
        let end: Int
    }
}

enum RectangularTextFixtureLoader {
    private static let supportedSchemaVersion = 1
    private static let supportedIndexing = "zero-based half-open ranges over visible monospace text"

    static func loadAll(from fixtureRoot: URL? = nil) throws -> [RectangularTextFixture] {
        let root: URL
        if let fixtureRoot {
            root = fixtureRoot
        } else {
            root = try resolveDefaultFixtureRoot()
        }

        let directoryURLs = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        .filter {
            let values = try $0.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )
            return values.isDirectory == true && values.isSymbolicLink != true
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !directoryURLs.isEmpty else {
            throw LoadingError("No rectangular text fixtures found at \(root.path)")
        }

        return try directoryURLs.map(loadFixture)
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
            "Could not locate tests/fixtures/rectangular-text from the test source or executable"
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

    private static func fixtureRoot(above startingURL: URL) -> URL? {
        var currentURL = startingURL.standardizedFileURL

        while true {
            let packageManifestURL = currentURL.appendingPathComponent("Package.swift")
            let fixtureRoot = currentURL
                .appendingPathComponent("tests", isDirectory: true)
                .appendingPathComponent("fixtures", isDirectory: true)
                .appendingPathComponent("rectangular-text", isDirectory: true)

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

    private static func loadFixture(from directoryURL: URL) throws -> RectangularTextFixture {
        let fixtureID = directoryURL.lastPathComponent
        let metadataURL = try fixtureFileURL(
            named: "selection.json",
            in: directoryURL,
            fixtureID: fixtureID
        )
        let metadataData = try Data(contentsOf: metadataURL)
        let metadata = try JSONDecoder().decode(RectangularTextFixture.Metadata.self, from: metadataData)

        guard metadata.schemaVersion == supportedSchemaVersion else {
            throw LoadingError(
                "Fixture \(fixtureID) uses unsupported schema version \(metadata.schemaVersion)"
            )
        }

        guard metadata.id == fixtureID else {
            throw LoadingError(
                "Fixture directory \(fixtureID) does not match metadata id \(metadata.id)"
            )
        }

        guard metadata.selection.indexing == supportedIndexing else {
            throw LoadingError("Fixture \(fixtureID) uses unsupported selection indexing")
        }

        try validate(metadata.selection.rows, named: "rows", fixtureID: fixtureID)
        try validate(metadata.selection.columns, named: "columns", fixtureID: fixtureID)

        let inputURL = try fixtureFileURL(
            named: metadata.input,
            in: directoryURL,
            fixtureID: fixtureID
        )
        let expectedOutputURL = try fixtureFileURL(
            named: metadata.expectedPlainTextOutput,
            in: directoryURL,
            fixtureID: fixtureID
        )
        let inputText = try String(contentsOf: inputURL, encoding: .utf8)
        let expectedPlainTextOutput = try String(contentsOf: expectedOutputURL, encoding: .utf8)
        let inputRows = inputText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)

        guard metadata.selection.rows.end <= inputRows.count else {
            throw LoadingError(
                "Fixture \(fixtureID) selects row \(metadata.selection.rows.end) "
                    + "but only \(inputRows.count) logical rows exist"
            )
        }

        guard !expectedPlainTextOutput.contains("\r"),
              !expectedPlainTextOutput.hasSuffix("\n")
        else {
            throw LoadingError(
                "Fixture \(fixtureID) expected output must use LF separators without a final newline"
            )
        }

        return RectangularTextFixture(
            metadata: metadata,
            inputText: inputText,
            expectedPlainTextOutput: expectedPlainTextOutput
        )
    }

    private static func validate(
        _ bounds: RectangularTextFixture.Bounds,
        named name: String,
        fixtureID: String
    ) throws {
        guard bounds.start >= 0, bounds.start < bounds.end else {
            throw LoadingError(
                "Fixture \(fixtureID) has invalid \(name) range [\(bounds.start), \(bounds.end))"
            )
        }
    }

    private static func fixtureFileURL(
        named fileName: String,
        in directoryURL: URL,
        fixtureID: String
    ) throws -> URL {
        guard !fileName.isEmpty,
              fileName != ".",
              fileName != "..",
              fileName == URL(fileURLWithPath: fileName).lastPathComponent,
              !fileName.contains("/"),
              !fileName.contains("\\")
        else {
            throw LoadingError("Fixture \(fixtureID) contains unsafe file path \(fileName)")
        }

        let fileURL = directoryURL.appendingPathComponent(fileName)
        let values: URLResourceValues
        do {
            values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        } catch {
            throw LoadingError("Fixture \(fixtureID) is missing \(fileName)")
        }

        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw LoadingError("Fixture \(fixtureID) path \(fileName) must be a regular file")
        }

        return fileURL
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
