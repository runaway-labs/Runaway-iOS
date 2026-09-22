import Foundation
import Testing
@testable import Runaway_iOS

@Suite("Coach week board presentation")
struct CoachWeekBoardPresentationTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private var today: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 12))!
    }

    @Test func todayUsesRecommendationThenValidCommitment() throws {
        let recommended = workout(id: "today", type: .easyRun, duration: 40, distance: 4)
        #expect(presentation([recommended]).days[0].status == .recommended)
        var committed = recommended
        committed.commitment = WorkoutCommitment(
            committedAt: today, source: .recommendation,
            prescriptionFingerprint: try WorkoutPrescriptionFingerprint.make(recommended),
            originalWorkoutID: recommended.id
        )
        #expect(presentation([committed]).days[0].status == .committed)
        committed.commitment = WorkoutCommitment(
            committedAt: today, source: .recommendation,
            prescriptionFingerprint: "stale-fingerprint", originalWorkoutID: committed.id
        )
        #expect(presentation([committed]).days[0].status == .recommended)
    }

    @Test func partialOutranksStoredCompletion() {
        var partial = workout(type: .strengthTraining, duration: 45, completed: true)
        partial.acceptedCompletion = AcceptedWorkoutCompletion(
            resultID: UUID(), completedAt: today, elapsedSeconds: 1_200, isPartial: true
        )
        let day = presentation([partial]).days[0]
        #expect(day.status == .partial)
        #expect(day.actions == [.reviewResult])
    }

    @Test func stalePaceNeverAppearsOutsideRunning() {
        let walk = workout(type: .walking, duration: 30, distance: 2, targetPace: "9:22 /mi")
        #expect(!presentation([walk]).days[0].dose.contains("9:22"))
    }

    @Test func pastRestIsRestAndMissingDoseIsSafe() {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let board = presentation([
            workout(date: yesterday, type: .rest),
            workout(id: "missing", type: .crossTraining)
        ])
        #expect(board.days[0].status == .rest)
        #expect(board.days[0].dose == "Recovery is part of the plan")
        #expect(board.days[1].dose == "Prescription details unavailable")
    }

    @Test func headerCountsOnlyTrainingSessionsAndMinutes() {
        let board = presentation([
            workout(id: "run", type: .easyRun, duration: 40),
            workout(id: "lift", type: .strengthTraining, duration: 45),
            workout(id: "rest", type: .rest)
        ])
        #expect(board.plannedSessionCount == 2)
        #expect(board.plannedMinutes == 85)
    }

    private func presentation(_ workouts: [DailyWorkout]) -> CoachWeekBoardPresentation {
        CoachWeekBoardPresentation.make(
            plan: plan(workouts), activities: [], recentDecision: nil,
            now: today, calendar: calendar, distanceFormatter: { "\($0) mi" }
        )
    }

    private func workout(id: String = "workout", date: Date? = nil, type: WorkoutType,
                         duration: Int? = nil, distance: Double? = nil,
                         targetPace: String? = nil, completed: Bool = false) -> DailyWorkout {
        let date = date ?? today
        return DailyWorkout(
            id: id, date: date, dayOfWeek: .from(date: date), workoutType: type,
            title: type.displayName, description: "Test prescription", duration: duration,
            distance: distance, targetPace: targetPace, exercises: nil,
            isCompleted: completed, completedActivityId: nil
        )
    }

    private func plan(_ workouts: [DailyWorkout]) -> WeeklyTrainingPlan {
        WeeklyTrainingPlan(
            id: "week", athleteId: 1, weekStartDate: calendar.startOfDay(for: today),
            weekEndDate: calendar.date(byAdding: .day, value: 6, to: calendar.startOfDay(for: today))!,
            workouts: workouts, weekNumber: nil,
            totalMileage: workouts.filter { $0.workoutType.isRunning }.compactMap(\.distance).reduce(0, +),
            focusArea: nil, notes: nil, generatedAt: today, goalId: nil
        )
    }
}
