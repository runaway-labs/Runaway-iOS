import XCTest
@testable import Runaway_iOS

@MainActor
final class CoachNarratorTests: XCTestCase {
    func testUnavailableModelUsesGroundedDeterministicNarration() async {
        let input = makeInput()

        let narration = await CoachNarrator().explain(input, generator: StubGenerator(isAvailable: false, output: ""))

        XCTAssertEqual(narration.provenance, .deterministic)
        XCTAssertTrue(narration.summary.contains(input.primaryChange.after))
        XCTAssertTrue(narration.detail.contains("Recovery declined"))
    }

    func testGenerationFailureFallsBackToDeterministicNarration() async {
        let input = makeInput()
        let narration = await CoachNarrator().explain(input, generator: StubGenerator(error: TestError.failed))

        XCTAssertEqual(narration.provenance, .deterministic)
        XCTAssertTrue(narration.summary.contains(input.primaryChange.after))
    }

    func testUnsupportedClaimIsDiscarded() async {
        let input = makeInput()
        let generated = "(input.primaryChange.after). This guarantees you will avoid injury. Recovery declined."

        let narration = await CoachNarrator().explain(input, generator: StubGenerator(output: generated))

        XCTAssertEqual(narration.provenance, .deterministic)
        XCTAssertFalse(narration.summary.localizedCaseInsensitiveContains("guarantees"))
    }

    func testChangedQuantityIsDiscarded() async {
        let input = makeInput()
        let generated = "Run 55 minutes instead. Recovery declined."

        let narration = await CoachNarrator().explain(input, generator: StubGenerator(output: generated))

        XCTAssertEqual(narration.provenance, .deterministic)
        XCTAssertTrue(narration.summary.contains("35 minutes"))
        XCTAssertFalse(narration.summary.contains("55"))
    }

    func testGroundedGenerationIsAccepted() async {
        let input = makeInput()
        let generated = "Easy Run - 35 minutes. Recovery declined, so this protects the quality still ahead."

        let narration = await CoachNarrator().explain(input, generator: StubGenerator(output: generated))

        XCTAssertEqual(narration.provenance, .onDevice)
        XCTAssertEqual(narration.summary, generated)
    }

    private func makeInput() -> CoachDecisionNarrationInput {
        CoachDecisionNarrationInput(
            athleteID: 7,
            decisionID: UUID(),
            state: .applied,
            primaryChange: CoachChange(
                kind: .reduced,
                workoutID: "easy-run",
                before: "Easy Run - 45 minutes",
                after: "Easy Run - 35 minutes",
                weeklyLoadDelta: -10,
                isKeyWorkout: false
            ),
            reasonCodes: [.recoveryDeclined],
            missingData: []
        )
    }
}

private struct StubGenerator: CoachTextGenerating {
    var isAvailable = true
    var output = ""
    var error: Error?

    func generate(prompt: String, systemPrompt: String, maxTokens: Int) async throws -> String {
        if let error { throw error }
        return output
    }
}

private enum TestError: Error { case failed }
