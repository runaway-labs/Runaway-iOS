import Foundation

enum BecomingChoice: String, CaseIterable, Identifiable, Sendable {
    case planned
    case easier
    case alternate
    case recover

    var id: String { rawValue }
}

enum BecomingDemand: Int, Comparable, Sendable {
    case low
    case moderate
    case high

    static func < (lhs: BecomingDemand, rhs: BecomingDemand) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct BecomingPath: Identifiable, Equatable, Sendable {
    let choice: BecomingChoice
    let title: String
    let effect: String
    let weekEffect: String
    let isRecommended: Bool

    var id: BecomingChoice { choice }
}

struct BecomingSnapshot: Equatable, Sendable {
    let headline: String
    let detail: String
    let recommendedChoice: BecomingChoice
    let paths: [BecomingPath]
}

enum BecomingEngine {
    static func simulate(
        readinessScore: Int?,
        plannedTitle: String,
        plannedDemand: BecomingDemand,
        alternativeTitles: [String],
        remainingSessionCount: Int
    ) -> BecomingSnapshot {
        let score = readinessScore.map { min(max($0, 0), 100) }
        let recommendedChoice: BecomingChoice
        let headline: String

        switch score {
        case .some(...44):
            recommendedChoice = .recover
            headline = "Protect tomorrow's capacity"
        case .some(45...69) where plannedDemand == .high:
            recommendedChoice = .easier
            headline = "Keep the week moving"
        default:
            recommendedChoice = .planned
            headline = "Build from today's choice"
        }

        let futureCount = max(remainingSessionCount, 0)
        let preservedWeek = "Keeps \(futureCount) future \(sessionWord(futureCount)) on their current path."
        let rebalancedWeek = "Rebalances \(futureCount) future \(sessionWord(futureCount)) after you choose."
        let firstAlternative = alternativeTitles
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && $0.caseInsensitiveCompare(plannedTitle) != .orderedSame }

        var choices: [(BecomingChoice, String, String, String)] = [
            (
                .planned,
                plannedTitle,
                plannedDemand == .high ? "Preserves today's quality stimulus." : "Preserves today's planned training stimulus.",
                preservedWeek
            ),
            (
                .easier,
                "Reduce the load",
                "Keeps momentum while lowering today's recovery cost.",
                rebalancedWeek
            )
        ]

        if recommendedChoice == .recover || firstAlternative == nil {
            choices.append((
                .recover,
                "Recovery day",
                "Leaves today's training load at zero and protects recovery.",
                rebalancedWeek
            ))
        } else if let firstAlternative {
            choices.append((
                .alternate,
                firstAlternative,
                "Changes the training stimulus without claiming an equal replacement.",
                rebalancedWeek
            ))
        }

        let paths = choices.map { choice, title, effect, weekEffect in
            BecomingPath(
                choice: choice,
                title: title,
                effect: effect,
                weekEffect: weekEffect,
                isRecommended: choice == recommendedChoice
            )
        }

        let detail = score == nil
            ? "Readiness is still calibrating. Compare safe paths without treating one score as certainty."
            : "Compare today's safe paths before the rest of your week is rebuilt."

        return BecomingSnapshot(
            headline: headline,
            detail: detail,
            recommendedChoice: recommendedChoice,
            paths: paths
        )
    }

    private static func sessionWord(_ count: Int) -> String {
        count == 1 ? "session" : "sessions"
    }
}
