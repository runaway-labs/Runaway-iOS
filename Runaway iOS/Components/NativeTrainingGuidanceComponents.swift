import SwiftUI

struct TodayWeatherChip: View {
    @StateObject private var context = NativeTrainingContextService.shared
    @StateObject private var locationManager = LocationManager.shared
    @State private var showingDetails = false

    private var state: TodayWeatherDisplayState {
        TodayWeatherDisplayPolicy.state(
            weather: context.weather,
            isLoading: context.isLoadingWeather,
            hasRequestedWeather: context.hasRequestedWeather,
            locationDenied: locationManager.isLocationDenied
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: openDetails) {
                HStack(spacing: 10) {
                    weatherIcon
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                        Text(detail)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }

                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open local weather details, \(title), \(detail)")

            Button(action: refresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.Colors.strideBlueLight.opacity(0.75))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Refresh local weather")
        }
        .padding(.leading, 13)
        .padding(.trailing, 1)
        .padding(.vertical, 4)
        .background(
            LinearGradient(
                colors: [
                    AppTheme.Colors.strideBlue.opacity(0.16),
                    AppTheme.Colors.success.opacity(0.08)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppTheme.Colors.strideBlue.opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .task { await requestAndLoadWeather() }
        .onChange(of: locationManager.location?.timestamp) { _, _ in
            guard let location = locationManager.location else { return }
            Task { await context.loadWeather(at: location) }
        }
        .sheet(isPresented: $showingDetails) {
            if let weather = context.weather {
                TodayWeatherDetailView(
                    weather: weather,
                    locationName: locationManager.weatherLocationString
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
            }
        }
    }

    @ViewBuilder
    private var weatherIcon: some View {
        switch state {
        case .waitingForLocation, .loading:
            ProgressView()
                .controlSize(.small)
                .tint(AppTheme.Colors.strideBlueLight)
        case .locationRequired:
            Image(systemName: "location.slash.fill")
                .foregroundColor(.yellow)
        case .unavailable:
            Image(systemName: "cloud.slash.fill")
                .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
        case let .available(weather):
            Image(systemName: weather.symbolName)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(AppTheme.Colors.strideBlueLight)
        }
    }

    private var title: String {
        if case let .available(weather) = state {
            return presentation(for: weather).title
        }
        return TodayWeatherCopy.title(for: state)
    }

    private var detail: String {
        if case let .available(weather) = state {
            let conditions = presentation(for: weather).detail
            guard !locationManager.weatherLocationString.isEmpty else { return conditions }
            return "\(locationManager.weatherLocationString) · \(conditions)"
        }
        return TodayWeatherCopy.detail(for: state)
    }

    private func refresh() {
        Task { await requestAndLoadWeather() }
    }

    private func openDetails() {
        if context.weather != nil {
            showingDetails = true
        } else {
            refresh()
        }
    }

    private func requestAndLoadWeather() async {
        switch TodayWeatherRefreshPolicy.action(hasLocation: locationManager.location != nil) {
        case .loadWeather:
            guard let location = locationManager.location else { return }
            await context.loadWeather(at: location)
        case .requestLocation:
            locationManager.requestLocationPermission()
            locationManager.requestSingleLocation()
        }
    }

    private func presentation(for weather: TrainingWeatherSnapshot) -> TodayWeatherPresentation {
        let usesCelsius = WeatherTemperatureDisplayPolicy.usesCelsius()
        return TodayWeatherCopy.presentation(for: weather, usesMetric: usesCelsius)
    }
}

private struct TodayWeatherDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let weather: TrainingWeatherSnapshot
    let locationName: String

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    private var usesCelsius: Bool {
        WeatherTemperatureDisplayPolicy.usesCelsius()
    }

    private var unitSuffix: String {
        usesCelsius ? "C" : "F"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    hero
                    precipitationSection
                    conditionsSection
                    gearSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            .navigationTitle("RunCast")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(AppTheme.Colors.strideBlueLight)
                }
            }
        }
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 18) {
            Image(systemName: weather.symbolName)
                .font(.system(size: 38, weight: .medium))
                .foregroundColor(AppTheme.Colors.strideBlueLight)
                .frame(width: 54, height: 54)
                .background(AppTheme.Colors.strideBlue.opacity(0.16), in: RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 5) {
                if !locationName.isEmpty {
                    Text(locationName)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
                }

                Text(currentTemperature)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()

                Text(heroDetail)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    private var precipitationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Rain outlook", symbol: "cloud.rain.fill")

            Text(precipitationSummary)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white)

            if !weather.hourlyForecast.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(weather.hourlyForecast) { hour in
                            VStack(spacing: 7) {
                                Text(hour.date.formatted(date: .omitted, time: .shortened))
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
                                Image(systemName: hour.symbolName)
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundColor(AppTheme.Colors.strideBlueLight)
                                Text("\(displayTemperature(hour.temperatureCelsius))°")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .monospacedDigit()
                                Label(
                                    "\(Int((hour.precipitationChance * 100).rounded()))%",
                                    systemImage: "drop.fill"
                                )
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundColor(AppTheme.Colors.strideBlueLight)
                            }
                            .frame(width: 66)
                            .padding(.vertical, 11)
                            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }
            }
        }
    }

    private var conditionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Conditions", symbol: "gauge.with.dots.needle.50percent")

            LazyVGrid(columns: columns, spacing: 10) {
                conditionMetric(
                    "Humidity",
                    value: "\(Int((weather.humidity * 100).rounded()))%",
                    symbol: "humidity.fill"
                )
                conditionMetric(
                    "Wind",
                    value: windLabel,
                    symbol: "wind"
                )
                conditionMetric(
                    "Rain peak",
                    value: "\(Int((RunCastPrecipitationPolicy.peakChance(for: weather) * 100).rounded()))%",
                    symbol: "drop.fill"
                )
                conditionMetric(
                    "UV index",
                    value: "\(weather.uvIndex)",
                    symbol: "sun.max.fill"
                )
            }
        }
    }

    private var gearSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("What to wear", symbol: "figure.run")

            VStack(spacing: 0) {
                ForEach(Array(RunCastGearPolicy.recommendations(for: weather).enumerated()), id: \.element.id) { index, item in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: item.symbolName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AppTheme.Colors.strideBlueLight)
                            .frame(width: 28, height: 28)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                            Text(item.detail)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 12)

                    if index < RunCastGearPolicy.recommendations(for: weather).count - 1 {
                        Divider().overlay(Color.white.opacity(0.06))
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func sectionHeader(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundColor(AppTheme.Colors.strideBlueLight)
            .textCase(.uppercase)
    }

    private func conditionMetric(_ title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppTheme.Colors.strideBlueLight)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                Text(title)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
    }

    private var currentTemperature: String {
        let celsius = weather.currentTemperatureCelsius ?? weather.feelsLikeCelsius
        return "\(displayTemperature(celsius))°"
    }

    private var heroDetail: String {
        var parts = ["Feels \(displayTemperature(weather.feelsLikeCelsius))°\(unitSuffix)"]
        if let high = weather.highCelsius, let low = weather.lowCelsius {
            parts.append("H \(displayTemperature(high))° · L \(displayTemperature(low))°")
        }
        return parts.joined(separator: " · ")
    }

    private var precipitationSummary: String {
        if let hour = RunCastPrecipitationPolicy.firstLikelyHour(in: weather.hourlyForecast) {
            let chance = Int((hour.precipitationChance * 100).rounded())
            let time = hour.date.formatted(date: .omitted, time: .shortened)
            return "Rain becomes possible around \(time) with a \(chance)% chance."
        }
        if let last = weather.hourlyForecast.last {
            return "Low rain risk through \(last.date.formatted(date: .omitted, time: .shortened))."
        }
        return "\(Int((weather.precipitationChance * 100).rounded()))% chance in the next hour."
    }

    private var windLabel: String {
        let speed = usesCelsius
            ? weather.windMetersPerSecond * 3.6
            : weather.windMetersPerSecond * 2.23694
        return "\(Int(speed.rounded())) \(usesCelsius ? "km/h" : "mph")"
    }

    private func displayTemperature(_ celsius: Double) -> Int {
        let unit: UnitTemperature = usesCelsius ? .celsius : .fahrenheit
        return Int(
            Measurement(value: celsius, unit: UnitTemperature.celsius)
                .converted(to: unit)
                .value
                .rounded()
        )
    }
}

struct NativeTrainingSummaryStrip: View {
    let workout: DailyWorkout
    @StateObject private var context = NativeTrainingContextService.shared
    @StateObject private var locationManager = LocationManager.shared

    private var target: TrainingZoneTarget? {
        NativeTrainingGuidancePolicy.zoneTarget(for: workout.workoutType)
    }

    private var weatherGuidance: WeatherTrainingGuidance? {
        NativeTrainingGuidancePolicy.guidanceIfRelevant(
            for: context.weather,
            workoutType: workout.workoutType
        )
    }

    private var conditionsState: WeatherConditionsDisplayState {
        WeatherConditionsDisplayPolicy.state(
            weather: context.weather,
            isLoading: context.isLoading || context.isLoadingWeather,
            hasRequestedWeather: context.hasRequestedWeather,
            locationDenied: locationManager.isLocationDenied,
            workoutType: workout.workoutType
        )
    }

    var body: some View {
        if target != nil || conditionsState != .hidden {
            VStack(spacing: 0) {
                if let target {
                    HStack(spacing: 10) {
                        Image(systemName: "waveform.path.ecg")
                            .foregroundColor(AppTheme.Colors.success)
                        Text(target.label)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                        Spacer(minLength: 0)
                        Text("Apple native")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundColor(AppTheme.Colors.DarkMode.textTertiary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                }

                if conditionsState != .hidden {
                    if target != nil {
                        Divider().overlay(Color.white.opacity(0.06))
                    }
                    conditionsRow
                }
            }
            .background((weatherGuidance?.requiresPlanReview == true ? Color.yellow : AppTheme.Colors.strideBlue).opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.small + 4))
        }
    }

    @ViewBuilder
    private var conditionsRow: some View {
        let presentation: (icon: String, tint: Color, detail: String) = {
            switch conditionsState {
            case .hidden:
                return ("", .clear, "")
            case .waitingForLocation:
                return ("location", AppTheme.Colors.strideBlueLight, "Getting your location...")
            case .loading:
                return ("cloud.sun", AppTheme.Colors.strideBlueLight, "Loading local forecast...")
            case .locationRequired:
                return ("location.slash", .yellow, "Allow location in Settings")
            case .unavailable:
                return ("exclamationmark.arrow.trianglehead.2.clockwise.rotate.90", .yellow, "Temporarily unavailable")
            case let .available(weather, guidance):
                return (weather.symbolName, conditionTint(for: guidance), conditionSummary(weather))
            }
        }()

        HStack(spacing: 10) {
            Image(systemName: presentation.icon)
                .foregroundColor(presentation.tint)
                .frame(width: 16)
            Text("Conditions")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
            Spacer(minLength: 8)
            Text(presentation.detail)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Conditions, \(presentation.detail)")
    }

    private func conditionTint(for guidance: WeatherTrainingGuidance) -> Color {
        switch guidance.level {
        case .favorable: return AppTheme.Colors.strideBlueLight
        case .caution: return .yellow
        case .high: return .orange
        }
    }

    private func conditionSummary(_ weather: TrainingWeatherSnapshot) -> String {
        let usesMetric = UnitPreferences.shared.distanceUnit == .kilometers
        let temperatureUnit: UnitTemperature = usesMetric ? .celsius : .fahrenheit
        let temperature = Measurement(value: weather.feelsLikeCelsius, unit: UnitTemperature.celsius)
            .converted(to: temperatureUnit).value.rounded()
        var details = ["Feels \(Int(temperature))°"]
        if weather.precipitationChance >= 0.20 {
            details.append("\(Int((weather.precipitationChance * 100).rounded()))% rain")
        }
        if weather.windMetersPerSecond >= 8 {
            let wind = usesMetric
                ? weather.windMetersPerSecond * 3.6
                : weather.windMetersPerSecond * 2.23694
            details.append("\(Int(wind.rounded())) \(usesMetric ? "km/h" : "mph") wind")
        }
        return details.joined(separator: " · ")
    }
}

struct NativeWorkoutContextCard: View {
    let workout: DailyWorkout
    @StateObject private var context = NativeTrainingContextService.shared
    @StateObject private var locationManager = LocationManager.shared
    @StateObject private var readinessService = ReadinessService.shared
    @State private var isScheduling = false
    @State private var deliveryMessage: String?
    @State private var deliverySucceeded = false

    private var target: TrainingZoneTarget? {
        NativeTrainingGuidancePolicy.zoneTarget(for: workout.workoutType)
    }

    private var calibration: ReadinessCalibrationAssessment {
        let availableWeight = readinessService.todaysReadiness?.factors.reduce(0) { $0 + $1.weight } ?? 0
        return ReadinessCalibrationPolicy.assessment(
            availableWeight: availableWeight,
            hasPersonalZones: context.heartRateZones != nil
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Native training intelligence", systemImage: "applewatch.radiowaves.left.and.right")
                .font(.headline)

            if let target {
                contextRow(
                    icon: "waveform.path.ecg",
                    tint: .cyan,
                    title: target.label + " · " + target.name,
                    detail: zoneDetail(target)
                )
            }

            if let weather = context.weather {
                let guidance = NativeTrainingGuidancePolicy.weatherGuidance(for: weather, workoutType: workout.workoutType)
                contextRow(
                    icon: weather.symbolName,
                    tint: guidance.level == .high ? .orange : (guidance.level == .caution ? .yellow : .teal),
                    title: guidance.title,
                    detail: weatherLine(weather) + "\n" + guidance.detail
                )
            } else if locationManager.isLocationDenied {
                contextRow(
                    icon: "location.slash",
                    tint: .secondary,
                    title: "Weather guidance off",
                    detail: "Enable location access to calibrate outdoor conditions."
                )
            }

            contextRow(
                icon: "scope",
                tint: calibration.level == .limited ? .orange : .teal,
                title: calibration.level.rawValue + " calibration confidence",
                detail: calibration.detail
            )

            if workout.workoutType.isRunning {
                Button {
                    Task { await scheduleWorkout() }
                } label: {
                    HStack {
                        if isScheduling { ProgressView().tint(.white) }
                        else { Image(systemName: deliverySucceeded ? "checkmark" : "applewatch") }
                        Text(deliverySucceeded ? "Scheduled on Apple Watch" : "Schedule on Apple Watch")
                        Spacer()
                        if !deliverySucceeded { Image(systemName: "chevron.right") }
                    }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(14)
                    .background(AppTheme.Colors.success)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(isScheduling || deliverySucceeded)
            }

            if let deliveryMessage {
                Text(deliveryMessage)
                    .font(.caption)
                    .foregroundColor(deliverySucceeded ? AppTheme.Colors.success : .orange)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .task {
            locationManager.requestLocationPermission()
            locationManager.requestSingleLocation()
            await context.refresh(at: locationManager.location)
        }
        .onChange(of: locationManager.location?.timestamp) { _, _ in
            guard let location = locationManager.location else { return }
            Task { await context.loadWeather(at: location) }
        }
    }

    private func contextRow(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold, design: .rounded))
                Text(detail)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func zoneDetail(_ target: TrainingZoneTarget) -> String {
        let range = context.heartRateZones?.bpmRange(for: target)
        let source = context.heartRateZones?.source.rawValue
        return [range, source, target.detail].compactMap { $0 }.joined(separator: " · ")
    }

    private func weatherLine(_ weather: TrainingWeatherSnapshot) -> String {
        TodayWeatherCopy.presentation(
            for: weather,
            usesMetric: WeatherTemperatureDisplayPolicy.usesCelsius()
        ).detail
    }

    private func scheduleWorkout() async {
        isScheduling = true
        defer { isScheduling = false }
        do {
            try await WorkoutDeliveryService.shared.schedule(workout)
            deliverySucceeded = true
            deliveryMessage = "The workout will appear in the Workout app on your paired Apple Watch."
        } catch {
            deliverySucceeded = false
            deliveryMessage = error.localizedDescription
        }
    }
}
