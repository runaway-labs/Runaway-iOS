import Foundation

/// Time-based calibration, not race prediction or a progression policy.
/// Input ownership, recency, limitations and today's completions are gated by the caller.
/// Assumptions: docs/superpowers/specs/2026-09-13-complete-running-prescriptions.md.
enum RunningPrescriptionPolicy {
    static let version = "running-prescription-v1"

    enum Result {
        case session(GoalSessionPreview.Running)
        case needsInput(String)
    }

    static func make(recordedElapsedSeconds: Double?, availableSeconds: Int) -> Result {
        guard availableSeconds >= 900 else {
            return .needsInput("This preview needs at least 15 available minutes, including warm-up and cooldown. Increase today's available time or choose another session.")
        }
        guard let elapsed = recordedElapsedSeconds, elapsed.isFinite, elapsed > 0 else {
            return .needsInput("Import a recent completed run or record current running ability before setting a timed run. Your target is not a measured baseline.")
        }
        // Clamp before converting to Int; elapsed can be finite but exceed Int.max.
        let work = min(Int(min(elapsed, 1_200)), availableSeconds - 600)
        guard work >= 300 else {
            return .needsInput("Record at least five minutes of completed running activity before using this preview. A shorter-session policy needs a separate assessment; do not skip the warm-up or cooldown.")
        }
        return .session(.init(
            warmupSeconds: 300, runningSeconds: work, cooldownSeconds: 300,
            effortInstruction: "Comfortable conversational effort. No pace target; slow down or pause if needed."
        ))
    }

    /// Display of an actual recorded distance, never an inferred prescription distance.
    static func distanceValue(meters: Double, unit: TrainingDistanceUnit) -> Double {
        meters / (unit == .miles ? 1_609.344 : 1_000)
    }
}
