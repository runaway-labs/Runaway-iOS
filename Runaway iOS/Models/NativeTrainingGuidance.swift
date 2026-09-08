import Foundation

struct TrainingZoneTarget: Equatable, Sendable {
    let lowerZone: Int
    let upperZone: Int
    let name: String
    let detail: String

    var label: String {
        lowerZone == upperZone ? "Zone \(lowerZone)" : "Zones \(lowerZone)-\(upperZone)"
    }
}

enum AppleTrainingZoneSource: String, Equatable, Sendable {
    case system = "Apple personalized"
    case user = "Custom in Health"
    case app = "Runaway"
}

struct AppleHeartRateZone: Equatable, Sendable, Identifiable {
    let index: Int
    let minimumBPM: Int?
    let maximumBPM: Int?

    var id: Int { index }
}

struct AppleHeartRateZoneSnapshot: Equatable, Sendable {
    let source: AppleTrainingZoneSource
    let zones: [AppleHeartRateZone]

    func bpmRange(for target: TrainingZoneTarget) -> String? {
        let selected = zones.filter { target.lowerZone...target.upperZone ~= $0.index }
        guard !selected.isEmpty else { return nil }
        let minimum = selected.compactMap(\.minimumBPM).min()
        let maximum = selected.compactMap(\.maximumBPM).max()
        switch (minimum, maximum) {
        case let (.some(low), .some(high)): return "\(low)-\(high) bpm"
        case let (.some(low), .none): return "\(low)+ bpm"
        case let (.none, .some(high)): return "Up to \(high) bpm"
        default: return nil
        }
    }
}

struct TrainingHourlyWeatherSnapshot: Equatable, Sendable, Identifiable {
    let date: Date
    let symbolName: String
    let temperatureCelsius: Double
    let precipitationChance: Double

    var id: Date { date }
}

struct TrainingWeatherSnapshot: Equatable, Sendable {
    let symbolName: String
    let feelsLikeCelsius: Double
    let humidity: Double
    let windMetersPerSecond: Double
    let precipitationChance: Double
    let uvIndex: Int
    let currentTemperatureCelsius: Double?
    let highCelsius: Double?
    let lowCelsius: Double?
    let hourlyForecast: [TrainingHourlyWeatherSnapshot]

    init(
        symbolName: String,
        feelsLikeCelsius: Double,
        humidity: Double,
        windMetersPerSecond: Double,
        precipitationChance: Double,
        uvIndex: Int,
        currentTemperatureCelsius: Double? = nil,
        highCelsius: Double? = nil,
        lowCelsius: Double? = nil,
        hourlyForecast: [TrainingHourlyWeatherSnapshot] = []
    ) {
        self.symbolName = symbolName
        self.feelsLikeCelsius = feelsLikeCelsius
        self.humidity = humidity
        self.windMetersPerSecond = windMetersPerSecond
        self.precipitationChance = precipitationChance
        self.uvIndex = uvIndex
        self.currentTemperatureCelsius = currentTemperatureCelsius
        self.highCelsius = highCelsius
        self.lowCelsius = lowCelsius
        self.hourlyForecast = hourlyForecast
    }
}

struct RunCastGearRecommendation: Equatable, Sendable, Identifiable {
    let title: String
    let detail: String
    let symbolName: String

    var id: String { title }
}

enum RunCastPrecipitationPolicy {
    static let likelyThreshold = 0.40

    static func firstLikelyHour(
        in forecast: [TrainingHourlyWeatherSnapshot]
    ) -> TrainingHourlyWeatherSnapshot? {
        forecast.first { $0.precipitationChance >= likelyThreshold }
    }

    static func peakChance(for weather: TrainingWeatherSnapshot) -> Double {
        max(
            weather.precipitationChance,
            weather.hourlyForecast.map(\.precipitationChance).max() ?? 0
        )
    }
}

enum RunCastGearPolicy {
    static func recommendations(for weather: TrainingWeatherSnapshot) -> [RunCastGearRecommendation] {
        var recommendations: [RunCastGearRecommendation] = []

        switch weather.feelsLikeCelsius {
        case 27...:
            recommendations.append(.init(
                title: "Lightweight kit",
                detail: "Breathable top, shorts, and extra fluids.",
                symbolName: "tshirt.fill"
            ))
        case 16..<27:
            recommendations.append(.init(
                title: "Easy layers",
                detail: "A light top and shorts should feel comfortable.",
                symbolName: "tshirt.fill"
            ))
        case 7..<16:
            recommendations.append(.init(
                title: "Add a light layer",
                detail: "Start with long sleeves or a removable quarter-zip.",
                symbolName: "jacket.fill"
            ))
        default:
            recommendations.append(.init(
                title: "Cold-weather layers",
                detail: "Use an insulating layer and protect hands and ears.",
                symbolName: "snowflake"
            ))
        }

        let peakRain = RunCastPrecipitationPolicy.peakChance(for: weather)
        if peakRain >= 0.55 {
            recommendations.append(.init(
                title: "Rain shell recommended",
                detail: "Choose a breathable shell and a brimmed cap.",
                symbolName: "cloud.rain.fill"
            ))
        } else if peakRain >= 0.25 {
            recommendations.append(.init(
                title: "Pack a light shell",
                detail: "A passing shower is possible during your window.",
                symbolName: "umbrella.fill"
            ))
        }

        if weather.windMetersPerSecond >= 8 {
            recommendations.append(.init(
                title: "Block the wind",
                detail: "A close-fitting wind layer will reduce chill.",
                symbolName: "wind"
            ))
        } else if weather.uvIndex >= 6 {
            recommendations.append(.init(
                title: "Sun protection",
                detail: "Use sunscreen, sunglasses, and a ventilated cap.",
                symbolName: "sun.max.fill"
            ))
        }

        return Array(recommendations.prefix(3))
    }
}

enum EnvironmentalLoadLevel: Equatable, Sendable {
    case favorable
    case caution
    case high
}

struct WeatherTrainingGuidance: Equatable, Sendable {
    let level: EnvironmentalLoadLevel
    let title: String
    let detail: String
    let intensityReduction: Double
    let affectsReadinessScore: Bool

    var requiresPlanReview: Bool {
        level == .caution || level == .high
    }
}

struct RaceWeatherSnapshot: Equatable, Sendable {
    let symbolName: String
    let highCelsius: Double
    let lowCelsius: Double
    let precipitationChance: Double
}

enum WeatherConditionsDisplayState: Equatable, Sendable {
    case hidden
    case waitingForLocation
    case loading
    case locationRequired
    case unavailable
    case available(TrainingWeatherSnapshot, WeatherTrainingGuidance)
}

enum TodayWeatherDisplayState: Equatable, Sendable {
    case waitingForLocation
    case loading
    case locationRequired
    case unavailable
    case available(TrainingWeatherSnapshot)
}

enum TodayWeatherDisplayPolicy {
    static func state(
        weather: TrainingWeatherSnapshot?,
        isLoading: Bool,
        hasRequestedWeather: Bool,
        locationDenied: Bool
    ) -> TodayWeatherDisplayState {
        if locationDenied { return .locationRequired }
        if let weather { return .available(weather) }
        if isLoading { return .loading }
        return hasRequestedWeather ? .unavailable : .waitingForLocation
    }
}

enum TodayWeatherRefreshAction: Equatable, Sendable {
    case requestLocation
    case loadWeather
}

enum TodayWeatherRefreshPolicy {
    static let timeoutSeconds: TimeInterval = 12

    static func action(hasLocation: Bool) -> TodayWeatherRefreshAction {
        hasLocation ? .loadWeather : .requestLocation
    }
}

struct TodayWeatherPresentation: Equatable, Sendable {
    let title: String
    let detail: String
}

enum WeatherTemperatureDisplayPolicy {
    static func usesCelsius(locale: Locale = .current) -> Bool {
        locale.measurementSystem != .us
    }
}

enum TodayWeatherCopy {
    static func title(for state: TodayWeatherDisplayState) -> String {
        "RunCast"
    }

    static func detail(for state: TodayWeatherDisplayState) -> String {
        switch state {
        case .waitingForLocation: return "Finding your starting line..."
        case .loading: return "Reading the sky..."
        case .locationRequired: return "Location unlocks your local outlook"
        case .unavailable: return "Forecast missed its split. Tap to retry."
        case .available: return "Conditions are ready"
        }
    }

    static func presentation(
        for weather: TrainingWeatherSnapshot,
        usesMetric: Bool
    ) -> TodayWeatherPresentation {
        let title: String
        let humidHeat = weather.feelsLikeCelsius >= 30 && weather.humidity >= 0.65
        if humidHeat || weather.feelsLikeCelsius >= 35 {
            title = "RunCast · Ease the effort"
        } else if weather.windMetersPerSecond >= 10 {
            title = "RunCast · Wind may affect pace"
        } else if weather.precipitationChance >= 0.55 {
            title = "RunCast · Rain likely"
        } else if weather.feelsLikeCelsius <= -5 {
            title = "RunCast · Warm up longer"
        } else if weather.uvIndex >= 7 {
            title = "RunCast · Seek some shade"
        } else {
            title = "RunCast · Great conditions"
        }

        let temperatureUnit: UnitTemperature = usesMetric ? .celsius : .fahrenheit
        let temperature = Measurement(value: weather.feelsLikeCelsius, unit: UnitTemperature.celsius)
            .converted(to: temperatureUnit).value.rounded()
        let precipitation = weather.precipitationChance < 0.20
            ? "Dry"
            : "\(Int((weather.precipitationChance * 100).rounded()))% rain"

        let wind: String
        if weather.windMetersPerSecond < 2 {
            wind = "Calm"
        } else if weather.windMetersPerSecond < 8 {
            wind = "Light breeze"
        } else {
            let speed = usesMetric
                ? weather.windMetersPerSecond * 3.6
                : weather.windMetersPerSecond * 2.23694
            wind = "\(Int(speed.rounded())) \(usesMetric ? "km/h" : "mph") wind"
        }

        return TodayWeatherPresentation(
            title: title,
            detail: "Feels \(Int(temperature))° · \(precipitation) · \(wind)"
        )
    }
}

enum WeatherConditionsDisplayPolicy {
    static func state(
        weather: TrainingWeatherSnapshot?,
        isLoading: Bool,
        hasRequestedWeather: Bool,
        locationDenied: Bool,
        workoutType: WorkoutType
    ) -> WeatherConditionsDisplayState {
        guard NativeTrainingGuidancePolicy.supportsWeather(for: workoutType) else {
            return .hidden
        }
        if locationDenied { return .locationRequired }
        if let weather,
           let guidance = NativeTrainingGuidancePolicy.guidanceIfRelevant(
            for: weather,
            workoutType: workoutType
           ) {
            return .available(weather, guidance)
        }
        if isLoading { return .loading }
        return hasRequestedWeather ? .unavailable : .waitingForLocation
    }
}

enum RaceWeatherForecastPolicy {
    static func isWithinForecastWindow(
        raceDate: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        let start = calendar.startOfDay(for: now)
        let raceDay = calendar.startOfDay(for: raceDate)
        guard let days = calendar.dateComponents([.day], from: start, to: raceDay).day else {
            return false
        }
        return (0...10).contains(days)
    }
}

enum TodayTrainingContextPresentationPolicy {
    static func shouldShow(
        plannedWorkout: DailyWorkout?,
        hasCompletedActivity: Bool
    ) -> Bool {
        plannedWorkout != nil && !hasCompletedActivity
    }
}

enum CalibrationConfidenceLevel: String, Equatable, Sendable {
    case high = "High"
    case moderate = "Moderate"
    case limited = "Limited"
}

struct ReadinessCalibrationAssessment: Equatable, Sendable {
    let level: CalibrationConfidenceLevel
    let detail: String
}

enum NativeTrainingGuidancePolicy {
    static func guidanceIfRelevant(
        for weather: TrainingWeatherSnapshot?,
        workoutType: WorkoutType
    ) -> WeatherTrainingGuidance? {
        guard let weather, supportsWeather(for: workoutType) else { return nil }
        return weatherGuidance(for: weather, workoutType: workoutType)
    }

    static func zoneTarget(for workoutType: WorkoutType) -> TrainingZoneTarget? {
        switch workoutType {
        case .recoveryRun:
            return TrainingZoneTarget(lowerZone: 1, upperZone: 2, name: "Recovery", detail: "Keep this genuinely light.")
        case .easyRun, .longRun:
            return TrainingZoneTarget(lowerZone: 2, upperZone: 2, name: "Conversational", detail: "Aerobic effort you can sustain comfortably.")
        case .tempoRun:
            return TrainingZoneTarget(lowerZone: 3, upperZone: 4, name: "Controlled quality", detail: "Build steadily without turning the workout into a race.")
        case .intervalRun, .hillRun:
            return TrainingZoneTarget(lowerZone: 4, upperZone: 5, name: "Hard repetitions", detail: "Use the high zones only during prescribed work intervals.")
        default:
            return nil
        }
    }

    static func weatherGuidance(
        for weather: TrainingWeatherSnapshot,
        workoutType: WorkoutType
    ) -> WeatherTrainingGuidance {
        guard supportsWeather(for: workoutType) else {
            return WeatherTrainingGuidance(
                level: .favorable,
                title: "Indoor plan unaffected",
                detail: "Weather is advisory only for this session.",
                intensityReduction: 0,
                affectsReadinessScore: false
            )
        }

        let humidHeat = weather.feelsLikeCelsius >= 30 && weather.humidity >= 0.65
        let extremeHeat = weather.feelsLikeCelsius >= 35
        if humidHeat || extremeHeat {
            return WeatherTrainingGuidance(
                level: .high,
                title: "High environmental load",
                detail: "Shift to an easy effort, hydrate early, or move the session to a cooler time.",
                intensityReduction: 0.20,
                affectsReadinessScore: false
            )
        }

        let strongWind = weather.windMetersPerSecond >= 10
        let likelyPrecipitation = weather.precipitationChance >= 0.55
        let cold = weather.feelsLikeCelsius <= -5
        let highUV = weather.uvIndex >= 7
        if strongWind || likelyPrecipitation || cold || highUV {
            let reason: String
            if strongWind { reason = "Strong wind will raise effort; run by feel instead of pace." }
            else if likelyPrecipitation { reason = "Wet conditions may affect footing and pace." }
            else if cold { reason = "Allow extra warm-up time before increasing effort." }
            else { reason = "High UV favors shade, protection, or a different start time." }
            return WeatherTrainingGuidance(
                level: .caution,
                title: "Conditions need an adjustment",
                detail: reason,
                intensityReduction: 0.10,
                affectsReadinessScore: false
            )
        }

        return WeatherTrainingGuidance(
            level: .favorable,
            title: "Conditions support the plan",
            detail: "No weather adjustment is recommended.",
            intensityReduction: 0,
            affectsReadinessScore: false
        )
    }

    static func supportsWeather(for workoutType: WorkoutType) -> Bool {
        switch workoutType {
        case .easyRun, .longRun, .tempoRun, .intervalRun, .hillRun, .recoveryRun,
             .cycling, .walking, .hiking:
            return true
        default:
            return false
        }
    }
}

enum ReadinessCalibrationPolicy {
    static func assessment(
        availableWeight: Double,
        hasPersonalZones: Bool
    ) -> ReadinessCalibrationAssessment {
        if availableWeight >= 0.85 && hasPersonalZones {
            return ReadinessCalibrationAssessment(
                level: .high,
                detail: "Strong Health signal coverage with personalized Apple zones."
            )
        }
        if availableWeight >= 0.60 {
            return ReadinessCalibrationAssessment(
                level: .moderate,
                detail: hasPersonalZones
                    ? "Useful signal coverage with personalized effort zones."
                    : "Useful signal coverage; Apple zones will improve effort calibration."
            )
        }
        return ReadinessCalibrationAssessment(
            level: .limited,
            detail: "The score is an estimate until more Health signals are available."
        )
    }
}
