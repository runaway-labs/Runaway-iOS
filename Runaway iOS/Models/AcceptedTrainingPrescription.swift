import Foundation
import CryptoKit

struct AcceptedTrainingPrescription: Codable, Equatable {
    let id: UUID
    let source: TrainingSessionResult.Reference
    let policyVersion: String
    let items: [SessionProgressionProposalPolicy.Item]
    let requiredSeconds: Int
    let massUnit: TrainingMassUnit
    let distanceUnit: TrainingDistanceUnit
    let evidenceIDs: [UUID]
    let rationale: String
    let acceptedAt: Date
}

struct AcceptedPrescriptionPlanReceipt: Codable, Identifiable {
    let id: UUID
    let before: WeeklyTrainingPlan
    let afterFingerprint: String
    let acceptedAt: Date
    let protectedStorageRevision: String?
    let activitiesFingerprint: String?

    init(before: WeeklyTrainingPlan, after: WeeklyTrainingPlan, acceptedAt: Date,
         protectedStorageRevision: String? = nil, activitiesFingerprint: String? = nil) throws {
        guard before.athleteId == after.athleteId, before.id == after.id else { throw AcceptedPrescriptionPlanError.staleReview }
        self.id = UUID()
        self.before = before
        self.afterFingerprint = try AcceptedPrescriptionPlanPolicy.fingerprint(after)
        self.acceptedAt = acceptedAt
        self.protectedStorageRevision = protectedStorageRevision
        self.activitiesFingerprint = activitiesFingerprint
    }

    func restoredPlan(current: WeeklyTrainingPlan, athleteID: Int) throws -> WeeklyTrainingPlan {
        guard athleteID == before.athleteId, current.athleteId == athleteID,
              try AcceptedPrescriptionPlanPolicy.fingerprint(current) == afterFingerprint else {
            throw AcceptedPrescriptionPlanError.staleUndo
        }
        return before
    }
}

enum AcceptedPrescriptionPlanError: LocalizedError {
    case staleReview, staleUndo, unavailableDay, protectedDay, invalidProposal, changedProtectedSession, timeConflict
    var errorDescription: String? {
        switch self {
        case .staleReview: return "Your account, training data or plan changed. Reopen the session preview and review a fresh proposal."
        case .staleUndo: return "The plan has changed since acceptance. Undo is blocked so newer work is not overwritten."
        case .unavailableDay: return "Choose an available future day in the current week. Today's training and next week's plan are not changed here."
        case .protectedDay: return "That day already has completed training. Choose another day."
        case .invalidProposal: return "A complete, evidence-backed prescription is required before accepting."
        case .changedProtectedSession: return "Regeneration changed a completed session or an explicit choice. No changes were saved."
        case .timeConflict: return "An adjusted session does not fit your saved daily availability. Update availability or choose another day. No changes were saved."
        }
    }
}

enum AcceptedPrescriptionPlanPolicy {
    static func fingerprint<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        encoder.dateEncodingStrategy = .iso8601
        return SHA256.hash(data: try encoder.encode(value)).map { String(format: "%02x", $0) }.joined()
    }

    static func isExplicitChoice(_ workout: DailyWorkout) -> Bool {
        workout.acceptedPrescription != nil || workout.description.hasPrefix("Chosen for today") ||
            workout.description.hasPrefix("Adjusted for today's readiness")
    }

    static func replacingWorkouts(in plan: WeeklyTrainingPlan, with workouts: [DailyWorkout], generatedAt: Date) -> WeeklyTrainingPlan {
        WeeklyTrainingPlan(id: plan.id, athleteId: plan.athleteId, weekStartDate: plan.weekStartDate, weekEndDate: plan.weekEndDate,
                           workouts: workouts.sorted { $0.date < $1.date }, weekNumber: plan.weekNumber,
                           totalMileage: workouts.filter { $0.workoutType.isRunning }.compactMap(\.distance).reduce(0, +),
                           focusArea: plan.focusArea, notes: plan.notes, generatedAt: generatedAt, goalId: plan.goalId)
    }

    static func placing(_ proposal: SessionProgressionProposalPolicy.Proposal, source: TrainingSessionResult.Reference,
                        in plan: WeeklyTrainingPlan, on date: Date, now: Date, calendar: Calendar = .current) throws -> WeeklyTrainingPlan {
        guard source.isValid, source.athleteID == plan.athleteId, !proposal.items.isEmpty,
              proposal.requiredSeconds > 0, proposal.requiredSeconds <= 86400, !proposal.evidenceIDs.isEmpty,
              proposal.items.count == source.items.count,
              Set(proposal.items.map(\.id)) == Set(source.items.map(\.id)),
              Set(plan.workouts.map(\.id)).count == plan.workouts.count,
              Set(plan.workouts.map { calendar.startOfDay(for: $0.date) }).count == plan.workouts.count else { throw AcceptedPrescriptionPlanError.invalidProposal }
        let day = calendar.startOfDay(for: date)
        guard day > calendar.startOfDay(for: now), plan.contains(date: day, calendar: calendar), plan.contains(date: now, calendar: calendar) else { throw AcceptedPrescriptionPlanError.unavailableDay }
        let original = plan.workouts.first { calendar.isDate($0.date, inSameDayAs: day) }
        guard original?.isCompleted != true, original?.completedActivityId == nil else { throw AcceptedPrescriptionPlanError.protectedDay }
        let prescription = AcceptedTrainingPrescription(id: UUID(), source: source, policyVersion: SessionProgressionProposalPolicy.version,
            items: proposal.items, requiredSeconds: proposal.requiredSeconds, massUnit: source.massUnit, distanceUnit: source.distanceUnit,
            evidenceIDs: proposal.evidenceIDs, rationale: proposal.reason, acceptedAt: now)
        let running = proposal.items.contains { $0.kind == .running }
        let details = proposal.items.map { "\($0.title): \(dose($0, unit: source.massUnit))" }.joined(separator: "\n")
        let exercises: [Exercise]? = running ? nil : proposal.items.filter { $0.kind == .strength }.map {
            Exercise(id: $0.id, name: $0.title, sets: 1, reps: $0.repetitions.map(String.init),
                     weight: dose($0, unit: source.massUnit), notes: "Accepted prescription; keep the original rest and setup allowances.")
        }
        var replacement = DailyWorkout(id: original?.id ?? UUID().uuidString, date: day, dayOfWeek: .from(date: day),
            workoutType: running ? .easyRun : .strengthTraining, title: source.goalTitle,
            description: "Accepted prescription.\n\(details)\nIncludes original rest and setup allowances.\n\(proposal.reason)",
            duration: Int(ceil(Double(proposal.requiredSeconds) / 60)), distance: nil,
            targetPace: running ? "Conversational effort; no target pace inferred" : nil,
            exercises: exercises, isCompleted: false, completedActivityId: nil)
        replacement.acceptedPrescription = prescription
        let remaining = plan.workouts.filter { !calendar.isDate($0.date, inSameDayAs: day) }
        return replacingWorkouts(in: plan, with: remaining + [replacement], generatedAt: now)
    }

    static func validateRegenerated(before: WeeklyTrainingPlan, after: WeeklyTrainingPlan, targetDate: Date,
                                    availability: [TrainingDayAvailability], now: Date, calendar: Calendar = .current) throws {
        guard before.id == after.id, before.athleteId == after.athleteId,
              before.weekStartDate == after.weekStartDate, before.weekEndDate == after.weekEndDate,
              Set(after.workouts.map { calendar.startOfDay(for: $0.date) }).count == after.workouts.count else { throw AcceptedPrescriptionPlanError.staleReview }
        for original in before.workouts {
            if original.isCompleted || isExplicitChoice(original) || calendar.startOfDay(for: original.date) <= calendar.startOfDay(for: now) {
                guard let updated = after.workouts.first(where: { $0.id == original.id }),
                      try fingerprint(updated) == fingerprint(original) else { throw AcceptedPrescriptionPlanError.changedProtectedSession }
            }
        }
        for updated in after.workouts where !updated.isCompleted && updated.workoutType != .rest && updated.date > calendar.startOfDay(for: now) {
            let old = before.workouts.first { calendar.isDate($0.date, inSameDayAs: updated.date) }
            let changed = try old.map { try fingerprint($0) != fingerprint(updated) } ?? true
            if changed || calendar.isDate(updated.date, inSameDayAs: targetDate) {
                guard let slot = availability.first(where: { $0.weekday == calendar.component(.weekday, from: updated.date) }),
                      slot.availableMinutes > 0, let minutes = updated.duration, minutes > 0, minutes <= slot.availableMinutes else { throw AcceptedPrescriptionPlanError.timeConflict }
            }
        }
    }

    static func dose(_ item: SessionProgressionProposalPolicy.Item, unit: TrainingMassUnit) -> String {
        if let seconds = item.seconds { return "\(Int(seconds) / 60) min \(Int(seconds) % 60) sec" }
        var value = "\(item.repetitions ?? 0) reps"
        let label = unit == .pounds ? "lb" : "kg"
        if let load = item.loadKilograms {
            value += " at \(SessionProgressionProposalPolicy.displayMass(load, unit: unit).formatted(.number.precision(.fractionLength(0...2)))) \(label)"
            value += item.convention == .perHand ? " per hand" : " total"
        } else { value += " at bodyweight" }
        if let assistance = item.assistanceKilograms {
            value += ", \(SessionProgressionProposalPolicy.displayMass(assistance, unit: unit).formatted(.number.precision(.fractionLength(0...2)))) \(label) assistance"
        }
        return value
    }
}
