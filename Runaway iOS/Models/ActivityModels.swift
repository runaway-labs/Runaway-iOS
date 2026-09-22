import Foundation
import SwiftUI

// MARK: - Model Layer Conventions
//
// Activity      — Supabase API model. Decodable from PostgREST JSON. Network/API layer.
//                 Full schema mirror of the `activities` table; owns all 40+ fields.
//
// LocalActivity — Lightweight view/display DTO. Passed to CardView, ActivityDetailView,
//                 and used for list selection state. Only carries the 7 fields that
//                 views actually need, using Swift-native types (Date vs TimeInterval).
//                 Created by converting from Activity (network) or SDActivity (persistence).
//                 Not Codable — never crosses a network or persistence boundary.
//
// SDActivity    — SwiftData persistence model. SD prefix = SwiftData convention.
//                 Adds offline-sync metadata: localId (UUID), syncStatus, server/local
//                 versioning. Lives in the local SwiftData store, not Supabase directly.
//
// Data flow:  Supabase JSON → Activity (decode) → SDActivity (persist) → LocalActivity (display)
//
// Do NOT conflate these types. Each layer has a distinct purpose and lifecycle.

// MARK: - Activity Models
public struct Activity: Identifiable, Codable, Equatable, Sendable {
    public let id: Int
    public let name: String?
    public let type: String?
    public let summary_polyline: String?
    public let distance: Double?
    public let start_date: TimeInterval?
    public let elapsed_time: TimeInterval?
    
    // Additional fields matching new schema
    public let athlete_id: Int?
    public let activity_type_id: Int?
    public let description: String?
    public let activity_date: TimeInterval?
    public let moving_time: Int?
    public let elevation_gain: Double?
    public let elevation_loss: Double?
    public let elevation_low: Double?
    public let elevation_high: Double?
    public let max_speed: Double?
    public let average_speed: Double?
    public let max_heart_rate: Int?
    public let average_heart_rate: Int?
    public let max_watts: Int?
    public let average_watts: Int?
    public let weighted_average_watts: Int?
    public let max_cadence: Int?
    public let average_cadence: Int?
    public let calories: Int?
    public let max_temperature: Double?
    public let average_temperature: Double?
    public let weather_condition: String?
    public let humidity: Double?
    public let wind_speed: Double?
    public let map_polyline: String?
    public let map_summary_polyline: String?
    public let start_latitude: Double?
    public let start_longitude: Double?
    public let end_latitude: Double?
    public let end_longitude: Double?
    public let commute: Bool?
    public let flagged: Bool?
    public let with_pet: Bool?
    public let competition: Bool?
    public let filename: String?
    public let gear_id: Int?
    public let device_name: String?
    public let source: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name, type, distance, elapsed_time
        case summary_polyline, start_date, athlete_id, activity_type_id
        case description, activity_date, moving_time
        case elevation_gain, elevation_loss, elevation_low, elevation_high
        case max_speed, average_speed, max_heart_rate, average_heart_rate
        case max_watts, average_watts, weighted_average_watts
        case max_cadence, average_cadence, calories
        case max_temperature, average_temperature, weather_condition
        case humidity, wind_speed, map_polyline, map_summary_polyline
        case start_latitude, start_longitude, end_latitude, end_longitude
        case commute, flagged, with_pet, competition, filename, gear_id
        case device_name, source
        case activity_types
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Required fields
        id = try container.decode(Int.self, forKey: .id)
        
        // Optional basic fields
        name = try container.decodeIfPresent(String.self, forKey: .name)

        // Handle type from nested activity_types object
        if let activityTypesData = try container.decodeIfPresent([String: String].self, forKey: .activity_types) {
            type = activityTypesData["name"]
        } else {
            type = try container.decodeIfPresent(String.self, forKey: .type)
        }
        distance = try container.decodeIfPresent(Double.self, forKey: .distance)
        elapsed_time = try container.decodeIfPresent(TimeInterval.self, forKey: .elapsed_time)

        // Handle polyline fields - ActivityService returns map_summary_polyline,
        // but CardView and other components expect summary_polyline
        if let mapSummaryPolyline = try container.decodeIfPresent(String.self, forKey: .map_summary_polyline) {
            summary_polyline = mapSummaryPolyline
        } else {
            summary_polyline = try container.decodeIfPresent(String.self, forKey: .summary_polyline)
        }
        
        // Handle date fields - ActivityService returns activity_date,
        // but CardView expects start_date
        var parsedActivityDate: TimeInterval?
        var parsedStartDate: TimeInterval?

        // Parse activity_date first (primary date field from database)
        if let dateString = try container.decodeIfPresent(String.self, forKey: .activity_date) {
            let formatter = ISO8601DateFormatter()
            if let date = formatter.date(from: dateString) {
                parsedActivityDate = date.timeIntervalSince1970
            }
        } else {
            parsedActivityDate = try container.decodeIfPresent(TimeInterval.self, forKey: .activity_date)
        }

        // Parse start_date (legacy field)
        if let dateString = try container.decodeIfPresent(String.self, forKey: .start_date) {
            let formatter = ISO8601DateFormatter()
            if let date = formatter.date(from: dateString) {
                parsedStartDate = date.timeIntervalSince1970
            }
        } else {
            parsedStartDate = try container.decodeIfPresent(TimeInterval.self, forKey: .start_date)
        }

        // Assign dates - use activity_date as start_date if start_date is not available
        activity_date = parsedActivityDate
        start_date = parsedStartDate ?? parsedActivityDate
        
        // New schema fields
        athlete_id = try container.decodeIfPresent(Int.self, forKey: .athlete_id)
        activity_type_id = try container.decodeIfPresent(Int.self, forKey: .activity_type_id)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        moving_time = try container.decodeIfPresent(Int.self, forKey: .moving_time)
        elevation_gain = try container.decodeIfPresent(Double.self, forKey: .elevation_gain)
        elevation_loss = try container.decodeIfPresent(Double.self, forKey: .elevation_loss)
        elevation_low = try container.decodeIfPresent(Double.self, forKey: .elevation_low)
        elevation_high = try container.decodeIfPresent(Double.self, forKey: .elevation_high)
        max_speed = try container.decodeIfPresent(Double.self, forKey: .max_speed)
        average_speed = try container.decodeIfPresent(Double.self, forKey: .average_speed)
        max_heart_rate = try container.decodeIfPresent(Int.self, forKey: .max_heart_rate)
        average_heart_rate = try container.decodeIfPresent(Int.self, forKey: .average_heart_rate)
        max_watts = try container.decodeIfPresent(Int.self, forKey: .max_watts)
        average_watts = try container.decodeIfPresent(Int.self, forKey: .average_watts)
        weighted_average_watts = try container.decodeIfPresent(Int.self, forKey: .weighted_average_watts)
        max_cadence = try container.decodeIfPresent(Int.self, forKey: .max_cadence)
        average_cadence = try container.decodeIfPresent(Int.self, forKey: .average_cadence)
        calories = try container.decodeIfPresent(Int.self, forKey: .calories)
        max_temperature = try container.decodeIfPresent(Double.self, forKey: .max_temperature)
        average_temperature = try container.decodeIfPresent(Double.self, forKey: .average_temperature)
        weather_condition = try container.decodeIfPresent(String.self, forKey: .weather_condition)
        humidity = try container.decodeIfPresent(Double.self, forKey: .humidity)
        wind_speed = try container.decodeIfPresent(Double.self, forKey: .wind_speed)
        map_polyline = try container.decodeIfPresent(String.self, forKey: .map_polyline)
        map_summary_polyline = try container.decodeIfPresent(String.self, forKey: .map_summary_polyline)
        start_latitude = try container.decodeIfPresent(Double.self, forKey: .start_latitude)
        start_longitude = try container.decodeIfPresent(Double.self, forKey: .start_longitude)
        end_latitude = try container.decodeIfPresent(Double.self, forKey: .end_latitude)
        end_longitude = try container.decodeIfPresent(Double.self, forKey: .end_longitude)
        commute = try container.decodeIfPresent(Bool.self, forKey: .commute)
        flagged = try container.decodeIfPresent(Bool.self, forKey: .flagged)
        with_pet = try container.decodeIfPresent(Bool.self, forKey: .with_pet)
        competition = try container.decodeIfPresent(Bool.self, forKey: .competition)
        filename = try container.decodeIfPresent(String.self, forKey: .filename)
        gear_id = try container.decodeIfPresent(Int.self, forKey: .gear_id)
        device_name = try container.decodeIfPresent(String.self, forKey: .device_name)
        source = try container.decodeIfPresent(String.self, forKey: .source)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        // Required fields
        try container.encode(id, forKey: .id)

        // Optional basic fields
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(type, forKey: .type)
        try container.encodeIfPresent(distance, forKey: .distance)
        try container.encodeIfPresent(elapsed_time, forKey: .elapsed_time)
        try container.encodeIfPresent(summary_polyline, forKey: .summary_polyline)

        // Handle date fields
        try container.encodeIfPresent(start_date, forKey: .start_date)
        try container.encodeIfPresent(activity_date, forKey: .activity_date)

        // New schema fields
        try container.encodeIfPresent(athlete_id, forKey: .athlete_id)
        try container.encodeIfPresent(activity_type_id, forKey: .activity_type_id)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(moving_time, forKey: .moving_time)
        try container.encodeIfPresent(elevation_gain, forKey: .elevation_gain)
        try container.encodeIfPresent(elevation_loss, forKey: .elevation_loss)
        try container.encodeIfPresent(elevation_low, forKey: .elevation_low)
        try container.encodeIfPresent(elevation_high, forKey: .elevation_high)
        try container.encodeIfPresent(max_speed, forKey: .max_speed)
        try container.encodeIfPresent(average_speed, forKey: .average_speed)
        try container.encodeIfPresent(max_heart_rate, forKey: .max_heart_rate)
        try container.encodeIfPresent(average_heart_rate, forKey: .average_heart_rate)
        try container.encodeIfPresent(max_watts, forKey: .max_watts)
        try container.encodeIfPresent(average_watts, forKey: .average_watts)
        try container.encodeIfPresent(weighted_average_watts, forKey: .weighted_average_watts)
        try container.encodeIfPresent(max_cadence, forKey: .max_cadence)
        try container.encodeIfPresent(average_cadence, forKey: .average_cadence)
        try container.encodeIfPresent(calories, forKey: .calories)
        try container.encodeIfPresent(max_temperature, forKey: .max_temperature)
        try container.encodeIfPresent(average_temperature, forKey: .average_temperature)
        try container.encodeIfPresent(weather_condition, forKey: .weather_condition)
        try container.encodeIfPresent(humidity, forKey: .humidity)
        try container.encodeIfPresent(wind_speed, forKey: .wind_speed)
        try container.encodeIfPresent(map_polyline, forKey: .map_polyline)
        try container.encodeIfPresent(map_summary_polyline, forKey: .map_summary_polyline)
        try container.encodeIfPresent(start_latitude, forKey: .start_latitude)
        try container.encodeIfPresent(start_longitude, forKey: .start_longitude)
        try container.encodeIfPresent(end_latitude, forKey: .end_latitude)
        try container.encodeIfPresent(end_longitude, forKey: .end_longitude)
        try container.encodeIfPresent(commute, forKey: .commute)
        try container.encodeIfPresent(flagged, forKey: .flagged)
        try container.encodeIfPresent(with_pet, forKey: .with_pet)
        try container.encodeIfPresent(competition, forKey: .competition)
        try container.encodeIfPresent(filename, forKey: .filename)
        try container.encodeIfPresent(gear_id, forKey: .gear_id)
        try container.encodeIfPresent(device_name, forKey: .device_name)
        try container.encodeIfPresent(source, forKey: .source)
    }

    public init(
        id: Int,
        name: String? = nil,
        type: String? = nil,
        summary_polyline: String? = nil,
        distance: Double? = nil,
        start_date: TimeInterval? = nil,
        elapsed_time: TimeInterval? = nil,
        athlete_id: Int? = nil,
        activity_type_id: Int? = nil,
        description: String? = nil,
        activity_date: TimeInterval? = nil,
        moving_time: Int? = nil,
        elevation_gain: Double? = nil,
        elevation_loss: Double? = nil,
        elevation_low: Double? = nil,
        elevation_high: Double? = nil,
        max_speed: Double? = nil,
        average_speed: Double? = nil,
        max_heart_rate: Int? = nil,
        average_heart_rate: Int? = nil,
        max_watts: Int? = nil,
        average_watts: Int? = nil,
        weighted_average_watts: Int? = nil,
        max_cadence: Int? = nil,
        average_cadence: Int? = nil,
        calories: Int? = nil,
        max_temperature: Double? = nil,
        average_temperature: Double? = nil,
        weather_condition: String? = nil,
        humidity: Double? = nil,
        wind_speed: Double? = nil,
        map_polyline: String? = nil,
        map_summary_polyline: String? = nil,
        start_latitude: Double? = nil,
        start_longitude: Double? = nil,
        end_latitude: Double? = nil,
        end_longitude: Double? = nil,
        commute: Bool? = nil,
        flagged: Bool? = nil,
        with_pet: Bool? = nil,
        competition: Bool? = nil,
        filename: String? = nil,
        gear_id: Int? = nil,
        device_name: String? = nil,
        source: String? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.summary_polyline = summary_polyline
        self.distance = distance
        self.start_date = start_date
        self.elapsed_time = elapsed_time
        self.athlete_id = athlete_id
        self.activity_type_id = activity_type_id
        self.description = description
        self.activity_date = activity_date
        self.moving_time = moving_time
        self.elevation_gain = elevation_gain
        self.elevation_loss = elevation_loss
        self.elevation_low = elevation_low
        self.elevation_high = elevation_high
        self.max_speed = max_speed
        self.average_speed = average_speed
        self.max_heart_rate = max_heart_rate
        self.average_heart_rate = average_heart_rate
        self.max_watts = max_watts
        self.average_watts = average_watts
        self.weighted_average_watts = weighted_average_watts
        self.max_cadence = max_cadence
        self.average_cadence = average_cadence
        self.calories = calories
        self.max_temperature = max_temperature
        self.average_temperature = average_temperature
        self.weather_condition = weather_condition
        self.humidity = humidity
        self.wind_speed = wind_speed
        self.map_polyline = map_polyline
        self.map_summary_polyline = map_summary_polyline
        self.start_latitude = start_latitude
        self.start_longitude = start_longitude
        self.end_latitude = end_latitude
        self.end_longitude = end_longitude
        self.commute = commute
        self.flagged = flagged
        self.with_pet = with_pet
        self.competition = competition
        self.filename = filename
        self.gear_id = gear_id
        self.device_name = device_name
        self.source = source
    }
}

/// Lightweight view/display DTO for activity data.
///
/// Contains only the 7 fields that UI components need, using Swift-native types
/// (`Date` instead of `TimeInterval`). Not `Codable` — never crosses a network
/// or persistence boundary.
///
/// Distinct from:
/// - `Activity` — Supabase API model (Codable, network layer, 40+ fields)
/// - `SDActivity` — SwiftData persistence model (offline-sync metadata, local DB layer)
///
/// Created by converting from `Activity` (network response) or `SDActivity` (local DB)
/// via `ActivityMapper.toLocalActivity(_:)` or the `convertToLocalActivity(_:)` helpers in views.
public struct LocalActivity: Identifiable, Hashable {
    public let id: Int
    public let name: String?
    public let type: String?
    public let summary_polyline: String?
    public let distance: Double?
    public let start_date: Date?
    public let elapsed_time: TimeInterval?
    
    public init(
        id: Int,
        name: String?,
        type: String?,
        summary_polyline: String? = nil,
        distance: Double?,
        start_date: Date?,
        elapsed_time: TimeInterval?
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.summary_polyline = summary_polyline
        self.distance = distance
        self.start_date = start_date
        self.elapsed_time = elapsed_time
    }
}

public struct Map: Codable {
    public let id: Int?
    public let map_id: String?
    public let summaryPolyline: String?
    public let polyline: String?

    public init(id: Int?, map_id: String?, summaryPolyline: String?, polyline: String?) {
        self.id = id
        self.map_id = map_id
        self.summaryPolyline = summaryPolyline
        self.polyline = polyline
    }
}

public struct ActivityDay: Identifiable {
    public let id = UUID()
    public var date: Date
    public var minutes: Double
    
    public init(date: Date, minutes: Double) {
        self.date = date
        self.minutes = minutes
    }
}

public struct RAActivity: Codable {
    public var day: String
    public var type: String?
    public var distance: Double
    public var time: Double
    
    public init(day: String, type: String?, distance: Double, time: Double) {
        self.day = day
        self.type = type
        self.distance = distance
        self.time = time
    }
}

// MARK: - Recording Models

// MARK: - Activity Creation Data
public struct ActivityCreationData {
    public let name: String
    public let type: String
    public let distance: Double // meters
    public let elapsedTime: TimeInterval // seconds
    public let startDate: Date
    public let summaryPolyline: String?
    public let userId: Int
    
    // Additional fields for new schema
    public let activityTypeId: Int?
    public let description: String?
    public let movingTime: Int?
    public let elevationGain: Double?
    public let polyline: String?
    public let startLatitude: Double?
    public let startLongitude: Double?
    public let endLatitude: Double?
    public let endLongitude: Double?
    
    public init(
        name: String,
        type: String,
        distance: Double,
        elapsedTime: TimeInterval,
        startDate: Date,
        summaryPolyline: String? = nil,
        userId: Int,
        activityTypeId: Int? = nil,
        description: String? = nil,
        movingTime: Int? = nil,
        elevationGain: Double? = nil,
        polyline: String? = nil,
        startLatitude: Double? = nil,
        startLongitude: Double? = nil,
        endLatitude: Double? = nil,
        endLongitude: Double? = nil
    ) {
        self.name = name
        self.type = type
        self.distance = distance
        self.elapsedTime = elapsedTime
        self.startDate = startDate
        self.summaryPolyline = summaryPolyline
        self.userId = userId
        self.activityTypeId = activityTypeId
        self.description = description
        self.movingTime = movingTime
        self.elevationGain = elevationGain
        self.polyline = polyline
        self.startLatitude = startLatitude
        self.startLongitude = startLongitude
        self.endLatitude = endLatitude
        self.endLongitude = endLongitude
    }
    
    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "name": name,
            "distance": distance,
            "elapsed_time": elapsedTime,
            "activity_date": startDate.iso8601String,
            "athlete_id": userId
        ]
        
        // Add activity type ID if provided, otherwise try to find by name
        if let activityTypeId = activityTypeId {
            dict["activity_type_id"] = activityTypeId
        }
        
        // Add optional fields
        if let description = description { dict["description"] = description }
        if let movingTime = movingTime { dict["moving_time"] = movingTime }
        if let elevationGain = elevationGain { dict["elevation_gain"] = elevationGain }
        if let polyline = polyline { dict["map_polyline"] = polyline }
        if let summaryPolyline = summaryPolyline { dict["map_summary_polyline"] = summaryPolyline }
        if let startLatitude = startLatitude { dict["start_latitude"] = startLatitude }
        if let startLongitude = startLongitude { dict["start_longitude"] = startLongitude }
        if let endLatitude = endLatitude { dict["end_latitude"] = endLatitude }
        if let endLongitude = endLongitude { dict["end_longitude"] = endLongitude }
        
        return dict
    }
}

extension Date {
    var iso8601String: String {
        return ISO8601DateFormatter().string(from: self)
    }
}
