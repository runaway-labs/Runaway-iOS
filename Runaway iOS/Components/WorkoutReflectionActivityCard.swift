import SwiftData
import SwiftUI

@MainActor
struct WorkoutReflectionActivityCard: View {
    @Environment(\.modelContext) private var modelContext

    let activity: LocalActivity

    @State private var reflection: WorkoutReflection?
    @State private var isPresentingSheet = false
    @State private var isSaving = false
    @State private var statusMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(spacing: AppTheme.Spacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium)
                        .fill(AppTheme.Colors.warmAmber.opacity(0.16))
                        .frame(width: 32, height: 32)
                    Image(systemName: "figure.mind.and.body")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.Colors.warmAmber)
                }
                EyebrowLabel(text: "POST-RUN REFLECTION", color: AppTheme.Colors.warmAmber)
            }

            if let reflection {
                HStack(spacing: AppTheme.Spacing.sm) {
                    reflectionPill("Effort \(reflection.perceivedEffort)/10")
                    reflectionPill(reflection.bodyState.rawValue.capitalized)
                    reflectionPill(moodLabel(reflection.mood))
                }

                Text(reflection.serverDebrief ?? reflection.localDebrief)
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.DarkMode.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Update reflection") {
                    statusMessage = nil
                    isPresentingSheet = true
                }
                .font(AppTheme.Typography.subheadlineBold)
                .foregroundStyle(AppTheme.Colors.warmAmber)
            } else {
                Text("Capture how this session felt while the details are still fresh.")
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.DarkMode.textSecondary)

                Button {
                    statusMessage = nil
                    isPresentingSheet = true
                } label: {
                    HStack {
                        Text("Reflect on this workout")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .font(AppTheme.Typography.subheadlineBold)
                    .foregroundStyle(AppTheme.Colors.pine)
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(AppTheme.Colors.strideLime)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large))
                }
                .buttonStyle(.plain)
            }

            if isSaving {
                Label("Building your debrief on this device...", systemImage: "apple.intelligence")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.DarkMode.textSecondary)
            } else if let statusMessage {
                Text(statusMessage)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.DarkMode.textTertiary)
            }
        }
        .padding(AppTheme.Spacing.lg)
        .background(AppTheme.Colors.DarkMode.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.large)
                .stroke(AppTheme.Colors.warmAmber.opacity(0.18), lineWidth: 1)
        }
        .task(id: activity.id) {
            loadReflection()
        }
        .sheet(isPresented: $isPresentingSheet) {
            WorkoutReflectionSheet(activityTitle: activity.name ?? activity.type ?? "Workout") { snapshot in
                Task { await save(snapshot) }
            }
        }
    }

    private func reflectionPill(_ text: String) -> some View {
        Text(text)
            .font(AppTheme.Typography.caption2)
            .foregroundStyle(AppTheme.Colors.amberLight)
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.vertical, AppTheme.Spacing.xs)
            .background(AppTheme.Colors.warmAmber.opacity(0.12))
            .clipShape(Capsule())
    }

    private func moodLabel(_ mood: ReflectionMood) -> String {
        switch mood {
        case .better: return "Proud"
        case .same: return "Steady"
        case .lower: return "Drained"
        }
    }

    private func loadReflection() {
        guard let userID = UserSession.shared.currentUser?.id else { return }

        do {
            reflection = try repository.reflection(activityId: activity.id, userId: userID)
        } catch {
            statusMessage = "Your reflection could not be loaded."
        }
    }

    private func save(_ snapshot: WorkoutReflectionFormSnapshot) async {
        guard let userID = UserSession.shared.currentUser?.id,
              let athleteID = UserSession.shared.userId else {
            statusMessage = "Sign in again to save this reflection."
            return
        }

        isSaving = true
        statusMessage = nil

        do {
            let now = Date()
            var savedReflection = try WorkoutReflection.validated(
                id: reflection?.id ?? UUID(),
                activityId: activity.id,
                userId: userID,
                athleteId: athleteID,
                perceivedEffort: snapshot.effort,
                bodyState: snapshot.bodyStatus.domainValue,
                mood: snapshot.mood.domainValue,
                conditionTags: snapshot.conditions.map(\.domainValue),
                note: snapshot.note,
                now: now
            )

            let summary = WorkoutActivitySummary(
                distanceMeters: activity.distance,
                elapsedSeconds: activity.elapsed_time,
                sportType: activity.type ?? "Workout"
            )
            savedReflection.localDebrief = WorkoutDebriefPolicy.debrief(for: savedReflection, activity: summary)

            try repository.upsert(savedReflection)
            reflection = savedReflection

            let generated = await WorkoutDebriefGenerator().generate(
                input: WorkoutDebriefInput(
                    effort: savedReflection.perceivedEffort,
                    bodyStatus: savedReflection.bodyState.rawValue,
                    mood: savedReflection.mood.rawValue,
                    conditionTags: savedReflection.conditionTags.map(\.rawValue),
                    note: savedReflection.note,
                    localDebrief: savedReflection.localDebrief,
                    activitySummary: activitySummaryText
                )
            )

            try repository.applyServerDebrief(localID: savedReflection.id, content: generated.text, generatedAt: Date())
            reflection = try repository.reflection(localID: savedReflection.id)

            do {
                let record = try await WorkoutReflectionRemoteService().save(
                    WorkoutReflectionUpload(
                        localId: savedReflection.id,
                        activityId: savedReflection.activityId,
                        effort: savedReflection.perceivedEffort,
                        bodyStatus: savedReflection.bodyState.rawValue,
                        mood: savedReflection.mood.rawValue,
                        conditionTags: savedReflection.conditionTags.map(\.rawValue),
                        note: savedReflection.note,
                        localDebrief: savedReflection.localDebrief,
                        enrichedDebrief: generated.text,
                        reflectedAt: savedReflection.updatedAt,
                        localVersion: 1
                    )
                )

                if let serverDebrief = record.serverDebrief {
                    try repository.applyServerDebrief(localID: savedReflection.id, content: serverDebrief, generatedAt: record.lastSyncedAt)
                }
                try repository.markSynced(localID: savedReflection.id, serverUpdatedAt: record.lastSyncedAt)
                reflection = try repository.reflection(localID: savedReflection.id)
                statusMessage = "Saved and synced."
            } catch {
                statusMessage = "Saved on this device. Sync pending."
            }
        } catch {
            statusMessage = "This reflection could not be saved. Please try again."
        }

        isSaving = false
    }

    private var repository: LocalWorkoutReflectionRepository {
        LocalWorkoutReflectionRepository(context: modelContext)
    }

    private var activitySummaryText: String {
        var details = [activity.type ?? "Workout"]
        if let distance = activity.distance {
            details.append(String(format: "%.0f meters", distance))
        }
        if let elapsed = activity.elapsed_time {
            details.append(String(format: "%.0f seconds", elapsed))
        }
        return details.joined(separator: ", ")
    }
}
