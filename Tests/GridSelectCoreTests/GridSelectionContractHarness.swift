import Foundation
import GridSelectCore

struct GridSelectionContractHarness {
    struct Snapshot: Equatable {
        let phase: GridSelectionContractFixture.Phase
        let selection: GridIndexSelection
    }

    struct Result {
        let snapshots: [Snapshot]
        let plainTextOutput: String?

        var finalSnapshot: Snapshot {
            snapshots.last!
        }
    }

    static func run(_ fixture: GridSelectionContractFixture) throws -> Result {
        var lifecycle = GridSelectionLifecycle()
        guard lifecycle.begin(GridActivation(generation: 1)) else {
            throw HarnessError("Fixture \(fixture.id) could not begin its lifecycle")
        }

        let anchor = fixture.metadata.start.anchor.gridBoundary
        let initialEffect: GridSelectionLifecycleEffect?
        switch fixture.metadata.start.method {
        case .keyboard:
            initialEffect = lifecycle.bindKeyboardAnchor(anchor)
        case .mouse:
            initialEffect = lifecycle.beginMouseSelection(at: anchor)
        }
        guard initialEffect != nil else {
            throw HarnessError("Fixture \(fixture.id) could not bind its initial anchor")
        }

        var snapshots = [try snapshot(of: lifecycle, fixtureID: fixture.id)]
        for (index, step) in fixture.metadata.steps.enumerated() {
            switch step.action {
            case .keyboardMove:
                guard let direction = step.direction?.gridDirection else {
                    throw HarnessError(
                        "Fixture \(fixture.id) step \(index + 1) has no direction"
                    )
                }
                for _ in 0..<step.effectiveRepeatCount {
                    guard lifecycle.moveKeyboardFocus(direction) != nil else {
                        throw HarnessError(
                            "Fixture \(fixture.id) step \(index + 1) keyboard move was rejected"
                        )
                    }
                }
            case .mouseMove:
                guard let boundary = step.boundary?.gridBoundary,
                      lifecycle.moveMouseFocus(to: boundary) != nil
                else {
                    throw HarnessError(
                        "Fixture \(fixture.id) step \(index + 1) mouse move was rejected"
                    )
                }
            case .freeze:
                guard lifecycle.freeze() != nil else {
                    throw HarnessError(
                        "Fixture \(fixture.id) step \(index + 1) freeze was rejected"
                    )
                }
            }
            snapshots.append(try snapshot(of: lifecycle, fixtureID: fixture.id))
        }

        let plainTextOutput = fixture.metadata.output.map {
            TextGrid(rows: $0.sourceRows).slice(
                rows: snapshots.last!.selection.rowRange,
                columns: snapshots.last!.selection.columnRange
            )
        }
        return Result(snapshots: snapshots, plainTextOutput: plainTextOutput)
    }

    private static func snapshot(
        of lifecycle: GridSelectionLifecycle,
        fixtureID: String
    ) throws -> Snapshot {
        switch lifecycle.state {
        case let .adjusting(_, selection):
            return Snapshot(phase: .adjusting, selection: selection)
        case let .selected(_, selection):
            return Snapshot(phase: .selected, selection: selection)
        case .inactive, .armed, .copying, .completed, .cancelled, .failed:
            throw HarnessError(
                "Fixture \(fixtureID) reached a state outside the selection contract"
            )
        }
    }

    struct HarnessError: LocalizedError {
        let message: String

        init(_ message: String) {
            self.message = message
        }

        var errorDescription: String? {
            message
        }
    }
}
