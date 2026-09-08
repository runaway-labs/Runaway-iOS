//
//  ReadinessService.swift
//  Runaway iOS
//
//  Calculates daily readiness/recovery scores based on HealthKit data and rest days
//  Formula: Sleep (25%) + HRV (20%) + Resting HR (15%) + Training Load (20%) + Rest Days (20%)
//

import Foundation
import Combine

@MainActor
class ReadinessService: ObservableObject {
    static let shared = ReadinessService()

    // MARK: - Published Properties

    @Published private(set) var todaysReadiness: DailyReadiness?
    @Published private(set) var isCalculating = false
    @Published private(set) var lastError: Error?

    // MARK: - Private Properties

    private let healthKitDataReader = HealthKitDataReader()
    private let restDayService = RestDayService.shared
    private let cacheKey = "cached_daily_readiness"
    private let cacheDuration: TimeInterval = 4 * 60 * 60 // 4 hours

    // MARK: - Initialization

    private init() {
        // Load cached readiness on init
        loadCachedReadiness()
    }

    // MARK: - Public Methods

    /// Calculate today's readiness score
    func calculateTodaysReadiness() async throws -> DailyReadiness {
        guard HealthKitManager.isHealthKitAvailable else {
            throw ReadinessError.healthKitNotAvailable
        }

        guard HealthKitManager.shared.isAuthorized else {
            throw ReadinessError.notAuthorized
        }

        isCalculating = true
        lastError = nil

        defer {
            Task { @MainActor in
                isCalculating = false
            }
        }

        let today = Date()

        // Fetch all health data in parallel
        async let sleepData = healthKitDataReader.fetchSleepAnalysis(for: today)
        async let hrvData = healthKitDataReader.fetchHRVData(for: today)
        async let restingHRData = healthKitDataReader.fetchRestingHeartRate(for: today)

        let sleep = try? await sleepData
        let hrv = try? await hrvData
        let restingHR = try? await restingHRData

        // Calculate training load from recent activities
        let trainingLoad = await calculateTrainingLoadScore()

        // Calculate rest day factor
        let athleteId = UserSession.shared.userId ?? 0
        let restDayFactor = await calculateRestDayFactor(athleteId: athleteId)

        // Build factors
        var factors: [ReadinessFactor] = []
        var totalWeightedScore = 0.0
        var totalWeight = 0.0

        // Sleep factor (25%)
        if let sleep = sleep {
            let factor = ReadinessFactor(
                id: ReadinessFactor.sleepId,
                name: "Sleep",
                score: sleep.qualityScore,
                weight: 0.25,
                value: formatDuration(minutes: sleep.totalSleepMinutes),
                change: nil,
                trend: sleep.totalSleepMinutes >= 420 ? .improving : (sleep.totalSleepMinutes >= 360 ? .stable : .declining)
            )
            factors.append(factor)
            totalWeightedScore += Double(factor.score) * factor.weight
            totalWeight += factor.weight
        }

        // HRV factor (20%)
        if let hrv = hrv {
            let changeText = hrv.percentFromBaseline.map { String(format: "%+.0f%%", $0) }
            let trend: ReadinessFactor.FactorTrend = {
                guard let percent = hrv.percentFromBaseline else { return .stable }
                if percent >= 5 { return .improving }
                if percent <= -10 { return .declining }
                return .stable
            }()

            let factor = ReadinessFactor(
                id: ReadinessFactor.hrvId,
                name: "HRV",
                score: hrv.score,
                weight: 0.20,
                value: String(format: "%.0f ms", hrv.value),
                change: changeText,
                trend: trend
            )
            factors.append(factor)
            totalWeightedScore += Double(factor.score) * factor.weight
            totalWeight += factor.weight
        }

        // Resting HR factor (15%)
        if let restingHR = restingHR {
            let changeText = restingHR.deviationFromBaseline.map { String(format: "%+d bpm", $0) }
            let trend: ReadinessFactor.FactorTrend = {
                guard let deviation = restingHR.deviationFromBaseline else { return .stable }
                if deviation <= -3 { return .improving }
                if deviation >= 5 { return .declining }
                return .stable
            }()

            let factor = ReadinessFactor(
                id: ReadinessFactor.restingHRId,
                name: "Resting HR",
                score: restingHR.score,
                weight: 0.15,
                value: "\(restingHR.value) bpm",
                change: changeText,
                trend: trend
            )
            factors.append(factor)
            totalWeightedScore += Double(factor.score) * factor.weight
            totalWeight += factor.weight
        }

        // Training load factor (20%)
        let trainingLoadFactorItem = ReadinessFactor(
            id: ReadinessFactor.trainingLoadId,
            name: "Training Load",
            score: trainingLoad.score,
            weight: 0.20,
            value: trainingLoad.description,
            change: nil,
            trend: trainingLoad.trend
        )
        factors.append(trainingLoadFactorItem)
        totalWeightedScore += Double(trainingLoadFactorItem.score) * trainingLoadFactorItem.weight
        totalWeight += trainingLoadFactorItem.weight

        // Rest days factor (20%)
        let restDaysFactorItem = ReadinessFactor(
            id: ReadinessFactor.restDaysId,
            name: "Rest Days",
            score: restDayFactor.score,
            weight: 0.20,
            value: restDayFactor.description,
            change: nil,
            trend: restDayFactor.trend
        )
        factors.append(restDaysFactorItem)
        totalWeightedScore += Double(restDaysFactorItem.score) * restDaysFactorItem.weight
        totalWeight += restDaysFactorItem.weight

        // Calculate overall score
        let overallScore: Int
        if totalWeight > 0 {
            overallScore = Self.normalizedScore(
                weightedScore: totalWeightedScore,
                availableWeight: totalWeight
            )
        } else {
            overallScore = 50 // Default if no data
        }

        // Generate personalized recommendation
        var recommendation = generateRecommendation(
            score: overallScore,
            sleep: sleep,
            hrv: hrv,
            restingHR: restingHR,
            trainingLoad: trainingLoad,
            restDays: restDayFactor
        )
        if totalWeight < 0.75 {
            recommendation = "Estimate based on available data. \(recommendation)"
        }

        let readiness = DailyReadiness(
            athleteId: athleteId,
            date: today,
            score: overallScore,
            factors: factors,
            recommendation: recommendation
        )

        // Cache and save
        todaysReadiness = readiness
        cacheReadiness(readiness)

        // Save to database
        Task {
            try? await saveReadinessToDatabase(readiness)
        }

        return readiness
    }

    /// Refresh readiness if stale (older than cache duration)
    func refreshIfNeeded() async {
        if let cached = todaysReadiness,
           cached.isToday,
           Date().timeIntervalSince(cached.calculatedAt) < cacheDuration {
            return
        }

        do {
            _ = try await calculateTodaysReadiness()
        } catch ReadinessError.healthKitNotAvailable, ReadinessError.notAuthorized {
            // HealthKit unavailable — compute score from training data alone so the banner always shows
            await calculateFallbackReadiness()
        } catch {
            lastError = error
            #if DEBUG
            print("Failed to calculate readiness: \(error.localizedDescription)")
            #endif
        }
    }

    /// Training-load-only readiness estimate used when HealthKit is unavailable.
    private func calculateFallbackReadiness() async {
        let athleteId = UserSession.shared.userId ?? 0
        async let trainingLoadResult = calculateTrainingLoadScore()
        async let restDayResult = calculateRestDayFactor(athleteId: athleteId)
        let (trainingLoad, restDayFactor) = await (trainingLoadResult, restDayResult)

        // Average the two available factors — weight them equally to 100
        let score = (trainingLoad.score + restDayFactor.score) / 2

        let factors = [
            ReadinessFactor(
                id: ReadinessFactor.trainingLoadId,
                name: "Training Load",
                score: trainingLoad.score,
                weight: 0.50,
                value: trainingLoad.description,
                change: nil,
                trend: trainingLoad.trend
            ),
            ReadinessFactor(
                id: ReadinessFactor.restDaysId,
                name: "Rest Days",
                score: restDayFactor.score,
                weight: 0.50,
                value: restDayFactor.description,
                change: nil,
                trend: restDayFactor.trend
            )
        ]

        let readiness = DailyReadiness(
            athleteId: athleteId,
            date: Date(),
            score: score,
            factors: factors,
            recommendation: generateRecommendation(
                score: score, sleep: nil, hrv: nil, restingHR: nil,
                trainingLoad: trainingLoad, restDays: restDayFactor
            )
        )
        todaysReadiness = readiness
        cacheReadiness(readiness)
    }

    // MARK: - Private Methods

    private func calculateTrainingLoadScore() async -> (score: Int, description: String, trend: ReadinessFactor.FactorTrend) {
        // Get recent activities to calculate ACWR (Acute:Chronic Workload Ratio)
        guard let athleteId = UserSession.shared.userId else {
            return (70, "No data", .stable)
        }

        do {
            // Fetch activities from last 28 days
            let activities = try await ActivityService.getAllActivitiesByUser(
                userId: athleteId,
                limit: 60
            )
            let trainingActivities = activities.filter {
                Self.isReadinessActivity(activityType: $0.type)
            }

            let today = Date()

            // Calculate acute load (last 7 days)
            let sevenDaysAgo = today.timeIntervalSince1970 - (7 * 24 * 60 * 60)
            let acuteActivities = trainingActivities.filter {
                guard let date = $0.activity_date else { return false }
                return date >= sevenDaysAgo
            }
            let acuteLoad = acuteActivities.reduce(0.0) { sum, activity in
                sum + calculateActivityLoad(activity)
            }

            // Calculate chronic load (8-28 days ago)
            let twentyEightDaysAgo = today.timeIntervalSince1970 - (28 * 24 * 60 * 60)
            let chronicActivities = trainingActivities.filter {
                guard let date = $0.activity_date else { return false }
                return date >= twentyEightDaysAgo && date < sevenDaysAgo
            }
            let chronicLoad = chronicActivities.reduce(0.0) { sum, activity in
                sum + calculateActivityLoad(activity)
            }

            // Calculate ACWR
            let averageChronicLoad = chronicLoad / 3.0 // Average per week
            let acwr: Double = averageChronicLoad > 0 ? acuteLoad / averageChronicLoad : 1.0

            // Score based on ACWR
            // Optimal ACWR is 0.8-1.3
            // Higher = overtraining risk, Lower = detraining
            let score: Int
            let description: String
            let trend: ReadinessFactor.FactorTrend

            if acwr >= 0.8 && acwr <= 1.3 {
                score = 85
                description = "Optimal"
                trend = .stable
            } else if acwr < 0.8 {
                score = 75
                description = "Light week"
                trend = .improving // Recovery
            } else if acwr <= 1.5 {
                score = 65
                description = "High load"
                trend = .declining
            } else {
                score = 45
                description = "Overreaching"
                trend = .declining
            }

            return (score, description, trend)

        } catch {
            return (70, "No data", .stable)
        }
    }

    nonisolated static func normalizedScore(weightedScore: Double, availableWeight: Double) -> Int {
        guard availableWeight > 0 else { return 50 }
        return min(100, max(0, Int((weightedScore / availableWeight).rounded())))
    }

    nonisolated static func isReadinessActivity(activityType: String?) -> Bool {
        guard let activityType else { return false }
        let normalized = activityType
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        let wholeBodyActivityMarkers = [
            "run", "jog", "trail",
            "ride", "bike", "cycling", "cycle",
            "swim",
            "strength", "weight", "crossfit", "functional training",
            "walk", "hike", "hiking",
            "mobility", "yoga", "pilates", "flexibility",
            "row", "elliptical", "stair", "cardio", "hiit"
        ]

        return wholeBodyActivityMarkers.contains { normalized.contains($0) }
    }

    private func calculateActivityLoad(_ activity: Activity) -> Double {
        // Simple TSS-like calculation: duration (hours) * intensity factor
        let elapsedTime = activity.elapsed_time ?? 0
        let durationHours = elapsedTime / 3600.0

        // Pace is meaningful for running; other supported activities use a
        // conservative duration-based load until richer HealthKit effort is available.
        let intensityFactor: Double
        let avgSpeed = activity.average_speed ?? 0
        if AppConstants.ActivityTypes.isRunning(activity.type), avgSpeed > 0 {
            // Faster pace = higher intensity
            let paceMinPerMile = (1609.34 / avgSpeed) / 60.0
            if paceMinPerMile < 7 {
                intensityFactor = 1.5 // Hard effort
            } else if paceMinPerMile < 9 {
                intensityFactor = 1.0 // Moderate
            } else {
                intensityFactor = 0.7 // Easy
            }
        } else {
            intensityFactor = 1.0
        }

        return durationHours * intensityFactor * 100 // Arbitrary scale
    }

    private func calculateRestDayFactor(athleteId: Int) async -> (score: Int, description: String, trend: ReadinessFactor.FactorTrend) {
        // Use RestDayService to calculate the rest day factor
        do {
            return try await restDayService.calculateRestDayFactor(athleteId: athleteId)
        } catch {
            #if DEBUG
            print("Failed to calculate rest day factor: \(error)")
            #endif
            // Default to adequate if we can't calculate
            return (70, "Unknown", .stable)
        }
    }

    private func generateRecommendation(
        score: Int,
        sleep: HealthKitDataReader.SleepAnalysis?,
        hrv: HealthKitDataReader.HRVData?,
        restingHR: HealthKitDataReader.RestingHRData?,
        trainingLoad: (score: Int, description: String, trend: ReadinessFactor.FactorTrend),
        restDays: (score: Int, description: String, trend: ReadinessFactor.FactorTrend)
    ) -> String {
        let level = DailyReadinessLevel.from(score: score)

        // Check for specific concerns
        var concerns: [String] = []

        if let sleep = sleep, sleep.totalSleepMinutes < 360 {
            concerns.append("low sleep")
        }

        if let hrv = hrv, let percent = hrv.percentFromBaseline, percent < -15 {
            concerns.append("HRV below baseline")
        }

        if let restingHR = restingHR, let deviation = restingHR.deviationFromBaseline, deviation > 5 {
            concerns.append("elevated resting HR")
        }

        if trainingLoad.score < 60 {
            concerns.append("high training load")
        }

        if restDays.score < 50 {
            concerns.append("rest day overdue")
        }

        // Generate specific recommendation
        if !concerns.isEmpty && score < 70 {
            let concernsText = concerns.joined(separator: ", ")
            return "Recovery compromised by \(concernsText). Consider an easy day or rest."
        }

        // If rest days are low but overall score is okay, still mention it
        if restDays.score < 60 && score >= 70 {
            return "\(level.recommendation) Consider scheduling a rest day soon."
        }

        return level.recommendation
    }

    private func formatDuration(minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }

    // MARK: - Caching

    private func cacheReadiness(_ readiness: DailyReadiness) {
        if let encoded = try? JSONEncoder().encode(readiness) {
            UserDefaults.standard.set(encoded, forKey: cacheKey)
        }
    }

    private func loadCachedReadiness() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let cached = try? JSONDecoder().decode(DailyReadiness.self, from: data),
              cached.isToday else {
            return
        }
        todaysReadiness = cached
    }

    // MARK: - Database Sync

    private func saveReadinessToDatabase(_ readiness: DailyReadiness) async throws {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]

        let data: [String: AnyEncodable] = [
            "athlete_id": AnyEncodable(readiness.athleteId),
            "date": AnyEncodable(dateFormatter.string(from: readiness.date)),
            "score": AnyEncodable(readiness.score),
            "sleep_score": AnyEncodable(readiness.factor(id: ReadinessFactor.sleepId)?.score),
            "hrv_score": AnyEncodable(readiness.factor(id: ReadinessFactor.hrvId)?.score),
            "resting_hr_score": AnyEncodable(readiness.factor(id: ReadinessFactor.restingHRId)?.score),
            "training_load_score": AnyEncodable(readiness.factor(id: ReadinessFactor.trainingLoadId)?.score),
            "recommendation": AnyEncodable(readiness.recommendation)
        ]

        // Upsert to database
        _ = try await supabase
            .from("daily_readiness")
            .upsert(data, onConflict: "athlete_id,date")
            .execute()
    }
}

// MARK: - Readiness Error

enum ReadinessError: LocalizedError {
    case healthKitNotAvailable
    case notAuthorized
    case noData
    case calculationFailed(Error)

    var errorDescription: String? {
        switch self {
        case .healthKitNotAvailable:
            return "HealthKit is not available on this device"
        case .notAuthorized:
            return "HealthKit authorization required for readiness calculation"
        case .noData:
            return "Not enough health data to calculate readiness"
        case .calculationFailed(let error):
            return "Failed to calculate readiness: \(error.localizedDescription)"
        }
    }
}
