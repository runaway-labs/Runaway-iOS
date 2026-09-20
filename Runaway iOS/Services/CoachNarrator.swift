import Foundation

@MainActor
protocol CoachTextGenerating {
    var isAvailable: Bool { get }
    func generate(prompt: String, systemPrompt: String, maxTokens: Int) async throws -> String
}

enum CoachNarrationProvenance: String, Equatable, Sendable {
    case deterministic
    case onDevice
}

struct CoachDecisionNarrationInput: Equatable, Sendable {
    let athleteID: Int
    let decisionID: UUID
    let state: CoachDecisionState
    let primaryChange: CoachChange
    let reasonCodes: [CoachReasonCode]
    let missingData: [String]

    init(decision: CoachDecision) {
        athleteID = decision.athleteID
        decisionID = decision.id
        state = decision.state
        primaryChange = decision.changes[0]
        reasonCodes = decision.reasonCodes
        missingData = decision.missingData
    }

    init(athleteID: Int, decisionID: UUID, state: CoachDecisionState,
         primaryChange: CoachChange, reasonCodes: [CoachReasonCode], missingData: [String]) {
        self.athleteID = athleteID
        self.decisionID = decisionID
        self.state = state
        self.primaryChange = primaryChange
        self.reasonCodes = reasonCodes
        self.missingData = missingData
    }
}

struct CoachNarration: Equatable, Sendable {
    let summary: String
    let detail: String
    let provenance: CoachNarrationProvenance
}

@MainActor
struct CoachNarrator {
    func explain(
        _ input: CoachDecisionNarrationInput,
        generator: any CoachTextGenerating = FoundationModelsService.shared
    ) async -> CoachNarration {
        let fallback = deterministicNarration(for: input)
        guard generator.isAvailable else { return fallback }

        do {
            let output = try await generator.generate(
                prompt: prompt(for: input),
                systemPrompt: systemPrompt,
                maxTokens: 120
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            guard validates(output, for: input) else { return fallback }
            return CoachNarration(
                summary: output,
                detail: "Explained privately on this device from the recorded coach decision.",
                provenance: .onDevice
            )
        } catch {
            return fallback
        }
    }

    private var systemPrompt: String {
        """
        Explain a deterministic training-plan decision in one concise sentence. Use only the supplied facts. Preserve every workout quantity exactly. Include the supplied reason. Never add medical claims, guarantees, diagnoses, new measurements, or new recommendations.
        """
    }

    private func prompt(for input: CoachDecisionNarrationInput) -> String {
        let reasons = input.reasonCodes.map(\.displayTitle).joined(separator: ", ")
        return "Before: \(input.primaryChange.before ?? "none"). After: \(input.primaryChange.after). Reason: \(reasons)."
    }

    private func deterministicNarration(for input: CoachDecisionNarrationInput) -> CoachNarration {
        let reason = input.reasonCodes.first?.displayTitle ?? "Training context changed"
        let verb = input.state == .proposed ? "Proposed" : "Updated"
        return CoachNarration(
            summary: "\(verb): \(input.primaryChange.after)",
            detail: "\(reason). The prescription comes from Runaway's deterministic training policy.",
            provenance: .deterministic
        )
    }

    private func validates(_ output: String, for input: CoachDecisionNarrationInput) -> Bool {
        guard !output.isEmpty,
              output.localizedCaseInsensitiveContains(input.primaryChange.after),
              input.reasonCodes.contains(where: { output.localizedCaseInsensitiveContains($0.displayTitle) }) else {
            return false
        }

        let prohibited = ["guarantee", "prevent injury", "diagnos", "cure", "definitely", "medical advice"]
        guard !prohibited.contains(where: output.localizedCaseInsensitiveContains) else { return false }

        let supplied = numericTokens(in: [input.primaryChange.before, input.primaryChange.after]
            .compactMap { $0 }.joined(separator: " "))
        return numericTokens(in: output).isSubset(of: supplied)
    }

    private func numericTokens(in text: String) -> Set<String> {
        guard let regex = try? NSRegularExpression(pattern: #"-?\d+(?:\.\d+)?"#) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return Set(regex.matches(in: text, range: range).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        })
    }
}

private extension CoachReasonCode {
    var displayTitle: String {
        switch self {
        case .workoutImported: return "Workout imported"
        case .workoutMissed: return "Workout missed"
        case .completionChanged: return "Completion changed"
        case .recoveryDeclined: return "Recovery declined"
        case .recoveryImproved: return "Recovery improved"
        case .weatherChanged: return "Weather changed"
        case .availabilityChanged: return "Availability changed"
        case .athleteRequested: return "Athlete requested"
        case .unsafeChange: return "Unsafe change"
        case .stalePlan: return "Plan changed"
        }
    }
}
