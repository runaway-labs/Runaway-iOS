import SwiftUI

struct AcceptedWorkoutCompletionPanel: View {
    let workout: DailyWorkout
    @Environment(DataManager.self) private var dataManager
    @State private var reference: TrainingSessionResult.Reference?
    @State private var showingRecorder = false
    @State private var showingHistory = false
    @State private var recorded = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(recorded ? "Completed work recorded" : "Make this work count", systemImage: recorded ? "checkmark.circle" : "square.and.pencil")
                .font(.headline)
            if let error {
                Text(error).font(.subheadline).foregroundStyle(.secondary)
            } else if let reference {
                if recorded {
                    Button("View completed session records") { showingHistory = true }
                } else if Calendar.current.startOfDay(for: workout.date) > Calendar.current.startOfDay(for: Date()) {
                    Text("Come back on or after the scheduled day to record what you actually completed.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Button("Record completed workout") { showingRecorder = true }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("recordAcceptedWorkout")
                    Text("Review actual time, reps, load and effort against this exact prescription. Saving contributes evidence for your next proposal; it does not automatically rewrite the week.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Color.clear.frame(height: 0)
                    .sheet(isPresented: $showingRecorder, onDismiss: finishRecording) {
                        TrainingSessionResultView(reference: reference, acceptedWorkout: workout)
                    }
                    .sheet(isPresented: $showingHistory) {
                        TrainingSessionHistoryView(athleteID: reference.athleteID)
                    }
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .tint(AppTheme.Colors.strideBlue)
        .task { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .trainingSessionInvalidated)) { _ in
            reference = nil; showingRecorder = false; showingHistory = false
            error = "Sign in to the account that owns this workout."
        }
    }

    @MainActor private func finishRecording() {
        do {
            try dataManager.refreshAcceptedWorkoutCompletions()
            reload()
        } catch {
            self.error = "Your saved records are safe, but plan status could not refresh. Reopen Plan to retry; do not record the workout again."
        }
    }

    @MainActor private func reload() {
        do {
            guard UserSession.shared.isReady, let athleteID = UserSession.shared.userId else {
                throw AcceptedPrescriptionCompletionPolicy.Failure.stalePlan
            }
            let value = try AcceptedPrescriptionCompletionPolicy.reference(for: workout, athleteID: athleteID)
            let records = try ProtectedTrainingRepository(activeAthleteID: {
                UserSession.shared.isReady ? UserSession.shared.userId : nil
            }).sessionResults(athleteID: athleteID)
            reference = value
            recorded = records.contains { $0.reference.id == value.id }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}
