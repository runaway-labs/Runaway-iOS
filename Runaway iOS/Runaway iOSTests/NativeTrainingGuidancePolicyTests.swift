import Foundation
import Testing
@testable import Runaway_iOS

struct NativeTrainingGuidancePolicyTests {
    @Test func easyAndLongRunsTargetConversationalZone() throws {
        let easy = try #require(NativeTrainingGuidancePolicy.zoneTarget(for: .easyRun))
        let long = try #require(NativeTrainingGuidancePolicy.zoneTarget(for: .longRun))

        #expect(easy.lowerZone == 2)
        #expect(easy.upperZone == 2)
        #expect(long == easy)
    }

    @Test func qualitySessionsUseHigherZonesWithoutPrescribingAllOutEffort() throws {
        let tempo = try #require(NativeTrainingGuidancePolicy.zoneTarget(for: .tempoRun))
        let intervals = try #require(NativeTrainingGuidancePolicy.zoneTarget(for: .intervalRun))

        #expect(tempo.lowerZone == 3)
        #expect(tempo.upperZone == 4)
        #expect(intervals.lowerZone == 4)
        #expect(intervals.upperZone == 5)
    }

    @Test func hotHumidWeatherProducesHighEnvironmentalLoad() {
        let weather = TrainingWeatherSnapshot(
            symbolName: "sun.max.fill",
            feelsLikeCelsius: 31,
            humidity: 0.78,
            windMetersPerSecond: 3,
            precipitationChance: 0,
            uvIndex: 8
        )

        let guidance = NativeTrainingGuidancePolicy.weatherGuidance(for: weather, workoutType: .tempoRun)

        #expect(guidance.level == .high)
        #expect(guidance.intensityReduction == 0.20)
        #expect(guidance.detail.contains("easy effort"))
    }

    @Test func strongWindProducesCautionWithoutChangingBiologicalReadiness() {
        let weather = TrainingWeatherSnapshot(
            symbolName: "wind",
            feelsLikeCelsius: 18,
            humidity: 0.45,
            windMetersPerSecond: 12,
            precipitationChance: 0.1,
            uvIndex: 3
        )

        let guidance = NativeTrainingGuidancePolicy.weatherGuidance(for: weather, workoutType: .easyRun)

        #expect(guidance.level == .caution)
        #expect(guidance.intensityReduction == 0.10)
        #expect(guidance.affectsReadinessScore == false)
    }

    @Test func normalConditionsDoNotInventAnAdjustment() {
        let weather = TrainingWeatherSnapshot(
            symbolName: "cloud.sun.fill",
            feelsLikeCelsius: 17,
            humidity: 0.50,
            windMetersPerSecond: 2,
            precipitationChance: 0.1,
            uvIndex: 2
        )

        let guidance = NativeTrainingGuidancePolicy.weatherGuidance(for: weather, workoutType: .longRun)

        #expect(guidance.level == .favorable)
        #expect(guidance.intensityReduction == 0)
    }

    @Test func unavailableWeatherIsQuietlyOmitted() {
        let guidance = NativeTrainingGuidancePolicy.guidanceIfRelevant(
            for: nil,
            workoutType: .easyRun
        )

        #expect(guidance == nil)
    }

    @Test func indoorSessionsDoNotReceiveWeatherGuidance() {
        let weather = TrainingWeatherSnapshot(
            symbolName: "cloud.heavyrain.fill",
            feelsLikeCelsius: 18,
            humidity: 0.85,
            windMetersPerSecond: 4,
            precipitationChance: 0.90,
            uvIndex: 1
        )

        #expect(NativeTrainingGuidancePolicy.guidanceIfRelevant(for: weather, workoutType: .strengthTraining) == nil)
        #expect(NativeTrainingGuidancePolicy.guidanceIfRelevant(for: weather, workoutType: .stretchMobility) == nil)
        #expect(NativeTrainingGuidancePolicy.guidanceIfRelevant(for: weather, workoutType: .swimming) == nil)
    }

    @Test func likelyRainOffersPlanReviewForAnOutdoorRun() throws {
        let weather = TrainingWeatherSnapshot(
            symbolName: "cloud.rain.fill",
            feelsLikeCelsius: 14,
            humidity: 0.82,
            windMetersPerSecond: 3,
            precipitationChance: 0.75,
            uvIndex: 1
        )

        let guidance = try #require(
            NativeTrainingGuidancePolicy.guidanceIfRelevant(for: weather, workoutType: .longRun)
        )

        #expect(guidance.level == .caution)
        #expect(guidance.requiresPlanReview)
        #expect(guidance.detail.contains("footing"))
    }

    @Test func coldConditionsRecommendExtraWarmup() throws {
        let weather = TrainingWeatherSnapshot(
            symbolName: "thermometer.low",
            feelsLikeCelsius: -8,
            humidity: 0.45,
            windMetersPerSecond: 2,
            precipitationChance: 0,
            uvIndex: 1
        )

        let guidance = try #require(
            NativeTrainingGuidancePolicy.guidanceIfRelevant(for: weather, workoutType: .easyRun)
        )

        #expect(guidance.level == .caution)
        #expect(guidance.detail.contains("warm-up"))
    }

    @Test func outdoorCyclingReceivesWeatherGuidance() throws {
        let weather = TrainingWeatherSnapshot(
            symbolName: "wind",
            feelsLikeCelsius: 18,
            humidity: 0.45,
            windMetersPerSecond: 12,
            precipitationChance: 0.1,
            uvIndex: 3
        )

        let guidance = try #require(
            NativeTrainingGuidancePolicy.guidanceIfRelevant(for: weather, workoutType: .cycling)
        )

        #expect(guidance.level == .caution)
        #expect(guidance.requiresPlanReview)
    }

    @Test func favorableWeatherDoesNotOfferPlanReview() throws {
        let weather = TrainingWeatherSnapshot(
            symbolName: "cloud.sun.fill",
            feelsLikeCelsius: 17,
            humidity: 0.50,
            windMetersPerSecond: 2,
            precipitationChance: 0.1,
            uvIndex: 2
        )

        let guidance = try #require(
            NativeTrainingGuidancePolicy.guidanceIfRelevant(for: weather, workoutType: .walking)
        )

        #expect(guidance.level == .favorable)
        #expect(!guidance.requiresPlanReview)
    }

    @Test func evaluatingWeatherNeverMutatesTheScheduledWorkout() throws {
        let date = Date(timeIntervalSince1970: 1_787_798_400)
        let workout = DailyWorkout(
            id: "weather-test",
            date: date,
            dayOfWeek: .thursday,
            workoutType: .tempoRun,
            title: "Tempo Run",
            description: "Planned quality session",
            duration: 45,
            distance: 6,
            targetPace: "8:00/mi",
            exercises: nil,
            isCompleted: false,
            completedActivityId: nil
        )
        let original = workout
        let weather = TrainingWeatherSnapshot(
            symbolName: "sun.max.fill",
            feelsLikeCelsius: 36,
            humidity: 0.70,
            windMetersPerSecond: 2,
            precipitationChance: 0,
            uvIndex: 9
        )

        _ = NativeTrainingGuidancePolicy.guidanceIfRelevant(for: weather, workoutType: workout.workoutType)

        #expect(workout.id == original.id)
        #expect(workout.date == original.date)
        #expect(workout.dayOfWeek == original.dayOfWeek)
        #expect(workout.workoutType == original.workoutType)
        #expect(workout.title == original.title)
        #expect(workout.description == original.description)
        #expect(workout.duration == original.duration)
        #expect(workout.distance == original.distance)
        #expect(workout.targetPace == original.targetPace)
        #expect(workout.isCompleted == original.isCompleted)
        #expect(workout.completedActivityId == original.completedActivityId)
    }

    @Test func raceWeatherAppearsOnlyInsideTheTenDayForecastWindow() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 28))!
        let inWindow = calendar.date(byAdding: .day, value: 10, to: now)!
        let tooFar = calendar.date(byAdding: .day, value: 11, to: now)!
        let past = calendar.date(byAdding: .day, value: -1, to: now)!

        #expect(RaceWeatherForecastPolicy.isWithinForecastWindow(raceDate: inWindow, now: now, calendar: calendar))
        #expect(!RaceWeatherForecastPolicy.isWithinForecastWindow(raceDate: tooFar, now: now, calendar: calendar))
        #expect(!RaceWeatherForecastPolicy.isWithinForecastWindow(raceDate: past, now: now, calendar: calendar))
    }

    @Test func lowReadinessPresentationDoesNotHidePlannedSessionContext() {
        let workout = DailyWorkout(
            id: "recovery-run",
            date: Date(timeIntervalSince1970: 1_787_798_400),
            dayOfWeek: .friday,
            workoutType: .recoveryRun,
            title: "Recovery Run",
            description: "Keep it conversational",
            duration: 30,
            distance: 3,
            targetPace: nil,
            exercises: nil,
            isCompleted: false,
            completedActivityId: nil
        )

        #expect(TodayTrainingContextPresentationPolicy.shouldShow(plannedWorkout: workout, hasCompletedActivity: false))
        #expect(!TodayTrainingContextPresentationPolicy.shouldShow(plannedWorkout: workout, hasCompletedActivity: true))
        #expect(!TodayTrainingContextPresentationPolicy.shouldShow(plannedWorkout: nil, hasCompletedActivity: false))
    }

    @Test func outdoorConditionsAlwaysExposeTheirCurrentState() {
        #expect(
            WeatherConditionsDisplayPolicy.state(
                weather: nil,
                isLoading: false,
                hasRequestedWeather: false,
                locationDenied: false,
                workoutType: .easyRun
            ) == .waitingForLocation
        )
        #expect(
            WeatherConditionsDisplayPolicy.state(
                weather: nil,
                isLoading: true,
                hasRequestedWeather: true,
                locationDenied: false,
                workoutType: .cycling
            ) == .loading
        )
        #expect(
            WeatherConditionsDisplayPolicy.state(
                weather: nil,
                isLoading: false,
                hasRequestedWeather: false,
                locationDenied: true,
                workoutType: .walking
            ) == .locationRequired
        )
        #expect(
            WeatherConditionsDisplayPolicy.state(
                weather: nil,
                isLoading: false,
                hasRequestedWeather: true,
                locationDenied: false,
                workoutType: .hiking
            ) == .unavailable
        )
    }

    @Test func indoorConditionsRemainHidden() {
        #expect(
            WeatherConditionsDisplayPolicy.state(
                weather: nil,
                isLoading: false,
                hasRequestedWeather: false,
                locationDenied: true,
                workoutType: .strengthTraining
            ) == .hidden
        )
    }

    @Test func todayWeatherRemainsVisibleForIndoorTrainingDays() {
        #expect(
            TodayWeatherDisplayPolicy.state(
                weather: nil,
                isLoading: false,
                hasRequestedWeather: false,
                locationDenied: false
            ) == .waitingForLocation
        )
        #expect(
            TodayWeatherDisplayPolicy.state(
                weather: nil,
                isLoading: true,
                hasRequestedWeather: true,
                locationDenied: false
            ) == .loading
        )
        #expect(
            TodayWeatherDisplayPolicy.state(
                weather: nil,
                isLoading: false,
                hasRequestedWeather: false,
                locationDenied: true
            ) == .locationRequired
        )
        #expect(
            TodayWeatherDisplayPolicy.state(
                weather: nil,
                isLoading: false,
                hasRequestedWeather: true,
                locationDenied: false
            ) == .unavailable
        )
    }

    @Test func todayWeatherExposesLoadedConditionsWithoutAWorkoutType() {
        let weather = TrainingWeatherSnapshot(
            symbolName: "cloud.sun.fill",
            feelsLikeCelsius: 19,
            humidity: 0.52,
            windMetersPerSecond: 3,
            precipitationChance: 0.15,
            uvIndex: 4
        )

        #expect(
            TodayWeatherDisplayPolicy.state(
                weather: weather,
                isLoading: false,
                hasRequestedWeather: true,
                locationDenied: false
            ) == .available(weather)
        )
    }

    @Test func todayWeatherLoadsDirectlyWhenLocationIsAlreadyKnown() {
        #expect(TodayWeatherRefreshPolicy.action(hasLocation: true) == .loadWeather)
        #expect(TodayWeatherRefreshPolicy.action(hasLocation: false) == .requestLocation)
        #expect(TodayWeatherRefreshPolicy.timeoutSeconds == 12)
    }

    @Test func todayWeatherCopyIsRunnerFacingAndDoesNotExposeFrameworkNames() {
        #expect(TodayWeatherCopy.title(for: .loading) == "RunCast")
        #expect(TodayWeatherCopy.detail(for: .loading) == "Reading the sky...")
        #expect(!TodayWeatherCopy.detail(for: .loading).localizedCaseInsensitiveContains("WeatherKit"))
    }

    @Test func favorableRunCastSummarizesUsefulConditions() {
        let weather = TrainingWeatherSnapshot(
            symbolName: "cloud.sun.fill",
            feelsLikeCelsius: 20,
            humidity: 0.45,
            windMetersPerSecond: 2.5,
            precipitationChance: 0.10,
            uvIndex: 3
        )

        let presentation = TodayWeatherCopy.presentation(for: weather, usesMetric: false)

        #expect(presentation.title == "RunCast · Great conditions")
        #expect(presentation.detail == "Feels 68° · Dry · Light breeze")
    }

    @Test func runCastTemperatureUnitFollowsDeviceRegionInsteadOfDistancePreference() {
        #expect(!WeatherTemperatureDisplayPolicy.usesCelsius(locale: Locale(identifier: "en_US")))
        #expect(WeatherTemperatureDisplayPolicy.usesCelsius(locale: Locale(identifier: "en_GB")))
        #expect(WeatherTemperatureDisplayPolicy.usesCelsius(locale: Locale(identifier: "fr_FR")))
    }

    @Test func runCastPrioritizesHeatAndHumidity() {
        let weather = TrainingWeatherSnapshot(
            symbolName: "sun.max.fill",
            feelsLikeCelsius: 32,
            humidity: 0.75,
            windMetersPerSecond: 2,
            precipitationChance: 0.05,
            uvIndex: 8
        )

        #expect(TodayWeatherCopy.presentation(for: weather, usesMetric: true).title == "RunCast · Ease the effort")
    }

    @Test func runCastCallsOutLikelyRain() {
        let weather = TrainingWeatherSnapshot(
            symbolName: "cloud.rain.fill",
            feelsLikeCelsius: 14,
            humidity: 0.80,
            windMetersPerSecond: 3,
            precipitationChance: 0.70,
            uvIndex: 2
        )

        let presentation = TodayWeatherCopy.presentation(for: weather, usesMetric: true)

        #expect(presentation.title == "RunCast · Rain likely")
        #expect(presentation.detail.contains("70% rain"))
    }

    @Test func runCastCallsOutStrongWind() {
        let weather = TrainingWeatherSnapshot(
            symbolName: "wind",
            feelsLikeCelsius: 18,
            humidity: 0.45,
            windMetersPerSecond: 11,
            precipitationChance: 0.10,
            uvIndex: 3
        )

        let presentation = TodayWeatherCopy.presentation(for: weather, usesMetric: false)

        #expect(presentation.title == "RunCast · Wind may affect pace")
        #expect(presentation.detail.contains("25 mph wind"))
    }

    @Test func runCastCallsOutColdStart() {
        let weather = TrainingWeatherSnapshot(
            symbolName: "thermometer.low",
            feelsLikeCelsius: -7,
            humidity: 0.45,
            windMetersPerSecond: 2,
            precipitationChance: 0.10,
            uvIndex: 1
        )

        #expect(TodayWeatherCopy.presentation(for: weather, usesMetric: true).title == "RunCast · Warm up longer")
    }

    @Test func runCastCallsOutHighUV() {
        let weather = TrainingWeatherSnapshot(
            symbolName: "sun.max.fill",
            feelsLikeCelsius: 24,
            humidity: 0.40,
            windMetersPerSecond: 2,
            precipitationChance: 0.05,
            uvIndex: 8
        )

        #expect(TodayWeatherCopy.presentation(for: weather, usesMetric: false).title == "RunCast · Seek some shade")
    }

    @Test func runCastFindsTheFirstLikelyRainHour() throws {
        let first = Date(timeIntervalSince1970: 1_788_192_000)
        let later = first.addingTimeInterval(3_600)
        let forecast = [
            TrainingHourlyWeatherSnapshot(
                date: first,
                symbolName: "cloud.fill",
                temperatureCelsius: 22,
                precipitationChance: 0.15
            ),
            TrainingHourlyWeatherSnapshot(
                date: later,
                symbolName: "cloud.rain.fill",
                temperatureCelsius: 21,
                precipitationChance: 0.65
            )
        ]

        #expect(RunCastPrecipitationPolicy.firstLikelyHour(in: forecast)?.date == later)
    }

    @Test func runCastRainPredictionAddsAppropriateClothingGuidance() {
        let weather = TrainingWeatherSnapshot(
            symbolName: "cloud.rain.fill",
            feelsLikeCelsius: 23,
            humidity: 0.75,
            windMetersPerSecond: 3,
            precipitationChance: 0.30,
            uvIndex: 2,
            hourlyForecast: [
                TrainingHourlyWeatherSnapshot(
                    date: Date(timeIntervalSince1970: 1_788_192_000),
                    symbolName: "cloud.rain.fill",
                    temperatureCelsius: 22,
                    precipitationChance: 0.70
                )
            ]
        )

        let recommendations = RunCastGearPolicy.recommendations(for: weather)

        #expect(recommendations.contains { $0.title == "Rain shell recommended" })
        #expect(RunCastPrecipitationPolicy.peakChance(for: weather) == 0.70)
    }

    @Test func runCastColdWindAddsLayersAndWindProtection() {
        let weather = TrainingWeatherSnapshot(
            symbolName: "wind",
            feelsLikeCelsius: 4,
            humidity: 0.45,
            windMetersPerSecond: 10,
            precipitationChance: 0.05,
            uvIndex: 1
        )

        let recommendations = RunCastGearPolicy.recommendations(for: weather)

        #expect(recommendations.contains { $0.title == "Cold-weather layers" })
        #expect(recommendations.contains { $0.title == "Block the wind" })
    }

    @Test func loadedOutdoorConditionsExposeWeatherAndGuidance() throws {
        let weather = TrainingWeatherSnapshot(
            symbolName: "cloud.rain.fill",
            feelsLikeCelsius: 14,
            humidity: 0.82,
            windMetersPerSecond: 3,
            precipitationChance: 0.75,
            uvIndex: 1
        )

        let state = WeatherConditionsDisplayPolicy.state(
            weather: weather,
            isLoading: false,
            hasRequestedWeather: true,
            locationDenied: false,
            workoutType: .longRun
        )
        guard case let .available(snapshot, guidance) = state else {
            Issue.record("Expected live outdoor conditions")
            return
        }

        #expect(snapshot == weather)
        #expect(guidance.level == .caution)
    }

    @Test func calibrationConfidenceRequiresSignalCoverageAndPersonalZones() {
        #expect(ReadinessCalibrationPolicy.assessment(availableWeight: 0.95, hasPersonalZones: true).level == .high)
        #expect(ReadinessCalibrationPolicy.assessment(availableWeight: 0.70, hasPersonalZones: false).level == .moderate)
        #expect(ReadinessCalibrationPolicy.assessment(availableWeight: 0.40, hasPersonalZones: true).level == .limited)
    }

    @Test func weatherLocationUsesCountyAndState() {
        #expect(
            WeatherLocationDisplayPolicy.label(
                county: "Cook County",
                state: "IL",
                cityStateFallback: "Chicago, IL"
            ) == "Cook County, IL"
        )
    }

    @Test func weatherLocationFallsBackToCityAndState() {
        #expect(
            WeatherLocationDisplayPolicy.label(
                county: nil,
                state: "IL",
                cityStateFallback: "Chicago, IL"
            ) == "Chicago, IL"
        )
    }
}
