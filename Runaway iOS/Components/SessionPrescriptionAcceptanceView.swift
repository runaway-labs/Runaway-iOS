import SwiftUI

struct SessionPrescriptionAcceptanceButton: View {
    let snapshot: TrainingSessionPreviewSnapshot
    let goal: AthleteTrainingGoal
    let proposal: SessionProgressionProposalPolicy.Proposal
    let athleteID: Int
    @State private var presented = false

    var body: some View {
        Button("Choose day and review week") { presented = true }
            .buttonStyle(.borderedProminent).tint(.blue)
            .sheet(isPresented: $presented) {
                SessionPrescriptionAcceptanceView(snapshot: snapshot, goal: goal, proposal: proposal, athleteID: athleteID)
            }
    }
}

private struct SessionPrescriptionAcceptanceView: View {
    let snapshot: TrainingSessionPreviewSnapshot
    let goal: AthleteTrainingGoal
    let proposal: SessionProgressionProposalPolicy.Proposal
    let athleteID: Int
    @Environment(DataManager.self) private var dataManager
    @Environment(\.dismiss) private var dismiss
    @State private var targetDate = Date()
    @State private var draft: Draft?
    @State private var busy = false
    @State private var confirmed = false
    @State private var errorMessage: String?
    @State private var accepted = false
    @State private var isLoadingPlan = true

    private struct Draft {
        let before: WeeklyTrainingPlan
        let after: WeeklyTrainingPlan
        let planFingerprint: String
        let activitiesFingerprint: String
        let profileFingerprint: String
        let cacheFingerprint: String?
        let reviewedOn: Date
    }

    private var futureRange: ClosedRange<Date>? {
        guard let plan = dataManager.currentWeeklyPlan, plan.athleteId == athleteID,
              let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) else { return nil }
        let end = Calendar.current.startOfDay(for: plan.weekEndDate)
        return tomorrow <= end ? tomorrow...end : nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(goal.title) {
                    Text("Accepting changes your live plan. The selected prescription is kept exact while the existing scheduler rebalances unprotected days around it.")
                    Text("Today is unchanged. Choose a future day in this week; next-week acceptance is not available here.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if accepted {
                    Section("Plan updated") {
                        Text("Your prescription and the reviewed weekly changes were saved together. Close this sheet to return to the comparison; Undo is available there while the plan and training data remain unchanged.")
                        Button("Done") { dismiss() }
                    }
                } else if isLoadingPlan {
                    Section { ProgressView("Opening your saved weekly plan...") }
                } else if let range = futureRange {
                    Section("Choose a day") {
                        DatePicker("Session date", selection: $targetDate, in: range, displayedComponents: .date)
                        Text("Reserved duration: \(proposal.requiredSeconds / 60) min \(proposal.requiredSeconds % 60) sec")
                        Button(busy ? "Preparing review..." : "Review this week's changes") {
                            Task { await prepare() }
                        }.disabled(busy)
                    }
                    if let draft {
                        Section("Before and after") {
                            ForEach(reviewDates(draft), id: \.self) { date in
                                let before = draft.before.workouts.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
                                let after = draft.after.workouts.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(date.formatted(.dateTime.weekday(.wide).month().day())).font(.headline)
                                    Text("Before: \(summary(before))").foregroundStyle(.secondary)
                                    Text("After: \(summary(after))")
                                    if let after, after.acceptedPrescription != nil {
                                        Text("Exact accepted prescription protected").font(.caption).foregroundStyle(.blue)
                                    }
                                    DisclosureGroup("Session details") {
                                        Text(after?.description ?? "No scheduled session")
                                            .font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                        }
                        Section("Recovery and scheduling review") {
                            ForEach(RemainingWeekTrainingPolicy.review(workouts: draft.after.workouts, results: snapshot.sessionResults, availability: snapshot.availability, on: draft.reviewedOn)) { day in
                                VStack(alignment: .leading) {
                                    Text(day.date.formatted(.dateTime.weekday(.wide))).font(.subheadline.weight(.semibold))
                                    Text(day.reason).font(.caption)
                                }
                            }
                            Text("These flags are not a guarantee of readiness. Time-based runs have no invented mileage; weekly mileage includes only sessions with a distance prescription.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Section {
                            Toggle("I reviewed the prescription and all weekly changes", isOn: $confirmed)
                            Button("Accept prescription and update week") { accept(draft) }
                                .disabled(!confirmed || busy)
                        }
                    }
                } else {
                    Section {
                        if let plan = dataManager.currentWeeklyPlan, plan.athleteId == athleteID, plan.isCurrentWeek {
                            Text("No future day remains in this week's plan. Next-week acceptance is not available here yet.")
                        } else {
                            Text("No current-week plan is saved for this account. Create one in Plan, then return here to review this prescription. Nothing has been generated or changed automatically.")
                        }
                    }
                }
                if let errorMessage {
                    Section("Nothing saved") { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Review your week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .task {
            let loaded = await dataManager.loadPlanForPrescriptionAcceptance(athleteID: athleteID)
            guard !Task.isCancelled else { return }
            if loaded, let range = futureRange { targetDate = range.lowerBound }
            isLoadingPlan = false
        }
        .onChange(of: targetDate) { _, _ in draft = nil; confirmed = false; errorMessage = nil }
        .onReceive(NotificationCenter.default.publisher(for: .trainingSessionInvalidated)) { _ in dismiss() }
    }

    private func requireFreshSnapshot() throws {
        guard UserSession.shared.isReady, UserSession.shared.userId == athleteID,
              Calendar.current.isDate(snapshot.generatedAt, inSameDayAs: Date()),
              let revision = snapshot.protectedStorageRevision,
              try ProtectedTrainingSnapshotRevision.capture(athleteID: athleteID) == revision,
              snapshot.goals.contains(where: { $0.id == goal.id && $0.isActive }) else { throw AcceptedPrescriptionPlanError.staleReview }
    }

    private func currentCacheFingerprint() throws -> String? {
        try TrainingPlanService.cachedPlanForProfileMigration().map { try AcceptedPrescriptionPlanPolicy.fingerprint($0) }
    }

    private func validateUnchanged(_ value: Draft) throws {
        try requireFreshSnapshot()
        guard Calendar.current.isDate(value.reviewedOn, inSameDayAs: Date()),
              let plan = dataManager.currentWeeklyPlan, plan.athleteId == athleteID,
              try AcceptedPrescriptionPlanPolicy.fingerprint(plan) == value.planFingerprint,
              try AcceptedPrescriptionPlanPolicy.fingerprint(dataManager.activities) == value.activitiesFingerprint,
              try currentCacheFingerprint() == value.cacheFingerprint else { throw AcceptedPrescriptionPlanError.staleReview }
        TrainingProfileStore.shared.reloadFromPersistence(existingPlan: plan)
        guard TrainingProfileStore.shared.profile.validated(existingPlan: plan).profile.fingerprint == value.profileFingerprint else { throw AcceptedPrescriptionPlanError.staleReview }
    }

    private func prepare() async {
        busy = true
        draft = nil
        confirmed = false
        errorMessage = nil
        defer { busy = false }
        do {
            try requireFreshSnapshot()
            let now = Date()
            guard let before = dataManager.currentWeeklyPlan, before.athleteId == athleteID,
                  let sourceID = proposal.evidenceIDs.first,
                  let source = snapshot.sessionResults.first(where: { $0.id == sourceID && $0.reference.goalID == goal.id }) else { throw AcceptedPrescriptionPlanError.staleReview }
            guard !dataManager.activities.contains(where: { activity in
                guard let stamp = activity.activity_date ?? activity.start_date else { return false }
                return Calendar.current.isDate(Date(timeIntervalSince1970: stamp), inSameDayAs: targetDate)
            }) else { throw AcceptedPrescriptionPlanError.protectedDay }
            TrainingProfileStore.shared.reloadFromPersistence(existingPlan: before)
            let profile = TrainingProfileStore.shared.profile.validated(existingPlan: before).profile
            let beforeHash = try AcceptedPrescriptionPlanPolicy.fingerprint(before)
            let activityHash = try AcceptedPrescriptionPlanPolicy.fingerprint(dataManager.activities)
            let cacheHash = try currentCacheFingerprint()
            let placed = try AcceptedPrescriptionPlanPolicy.placing(proposal, source: source.reference, in: before, on: targetDate, now: now)
            let regenerated = try await TrainingPlanService.generatePlan(athleteId: athleteID, profile: profile, scope: .remainingCurrentWeek, existingPlan: placed, regenerationDate: now)
            try AcceptedPrescriptionPlanPolicy.validateRegenerated(before: placed, after: regenerated, targetDate: targetDate, availability: snapshot.availability, now: now)
            let review = Draft(before: before, after: regenerated, planFingerprint: beforeHash, activitiesFingerprint: activityHash,
                               profileFingerprint: profile.fingerprint, cacheFingerprint: cacheHash, reviewedOn: now)
            try validateUnchanged(review)
            draft = review
        } catch { errorMessage = error.localizedDescription }
    }

    private func accept(_ value: Draft) {
        do {
            try validateUnchanged(value)
            let profile = TrainingProfileStore.shared.profile.validated(existingPlan: value.before).profile
            let receipt = try AcceptedPrescriptionPlanReceipt(before: value.before, after: value.after, acceptedAt: Date(),
                protectedStorageRevision: snapshot.protectedStorageRevision, activitiesFingerprint: value.activitiesFingerprint)
            try dataManager.updateCurrentWeeklyPlan(value.after, profile: profile, acceptedReceipt: receipt)
            accepted = true
            draft = nil
        } catch { errorMessage = error.localizedDescription; draft = nil; confirmed = false }
    }

    private func reviewDates(_ value: Draft) -> [Date] {
        Set((value.before.workouts + value.after.workouts).map { Calendar.current.startOfDay(for: $0.date) }).sorted()
    }

    private func summary(_ workout: DailyWorkout?) -> String {
        guard let workout else { return "No session" }
        return workout.title + (workout.duration.map { " · \($0) min" } ?? "") + (workout.isCompleted ? " · completed" : "")
    }
}

struct AcceptedPrescriptionUndoPanel: View {
    let athleteID: Int
    @Environment(DataManager.self) private var dataManager
    @State private var receipt: AcceptedPrescriptionPlanReceipt?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let receipt {
                Text("Last accepted weekly change").font(.subheadline.weight(.semibold))
                Text(receipt.acceptedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                Button("Undo last accepted change", role: .destructive) { undo(receipt) }
            }
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
        }
        .task(id: dataManager.currentWeeklyPlan?.generatedAt) {
            await dataManager.loadPlanForPrescriptionAcceptance(athleteID: athleteID)
            guard !Task.isCancelled else { return }
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .trainingSessionInvalidated)) { _ in receipt = nil; message = nil }
    }

    private func reload() {
        guard UserSession.shared.isReady, UserSession.shared.userId == athleteID else { receipt = nil; return }
        TrainingProfileStore.shared.reloadFromPersistence(existingPlan: dataManager.currentWeeklyPlan)
        receipt = TrainingPlanService.latestAcceptedReceipt(for: TrainingProfileStore.shared.profile, athleteID: athleteID)
    }

    private func undo(_ value: AcceptedPrescriptionPlanReceipt) {
        do {
            guard UserSession.shared.isReady, UserSession.shared.userId == athleteID,
                  let current = dataManager.currentWeeklyPlan, current.isCurrentWeek,
                  let revision = value.protectedStorageRevision,
                  try ProtectedTrainingSnapshotRevision.capture(athleteID: athleteID) == revision,
                  try AcceptedPrescriptionPlanPolicy.fingerprint(dataManager.activities) == value.activitiesFingerprint,
                  let cached = TrainingPlanService.cachedPlanForProfileMigration(),
                  try AcceptedPrescriptionPlanPolicy.fingerprint(cached) == AcceptedPrescriptionPlanPolicy.fingerprint(current) else { throw AcceptedPrescriptionPlanError.staleUndo }
            let restored = try value.restoredPlan(current: current, athleteID: athleteID)
            try dataManager.updateCurrentWeeklyPlan(restored)
            receipt = nil
            message = "The previous plan was restored. Completed-session records were not changed."
        } catch { message = error.localizedDescription }
    }
}
