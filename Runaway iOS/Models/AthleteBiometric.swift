import Foundation

struct AthleteBiometric: Codable, Identifiable {
    let id: UUID?
    let athleteId: Int
    let entryDate: String // YYYY-MM-DD
    let hrvMs: Double?
    let rhrBpm: Int?
    let sleepScore: Int?
    let readinessScore: Int?
    let recoveryPhase: String?
    let stressLevel: Double?
    let rawSource: String?
    let hrvBaselineMs: Double?
    let rhrBaselineBpm: Double?
    let sleepMinutes: Int?
    let deepSleepMinutes: Int?
    let remSleepMinutes: Int?
    let coreSleepMinutes: Int?
    let awakeMinutes: Int?
    let sleepStartAt: Date?
    let sleepEndAt: Date?
    let vo2Max: Double?
    let vo2MaxCycling: Double?
    let fitnessAge: Double?
    let bodyBattery: Double?
    let bodyBatteryHigh: Double?
    let bodyBatteryLow: Double?
    let bodyBatteryCharged: Double?
    let bodyBatteryDrained: Double?
    let respirationRate: Double?
    let spo2Percent: Double?
    let hrvStatus: String?
    let sleepQualifier: String?
    let steps: Int?
    let trainingStatus: String?
    let trainingLoad: Double?
    let recoveryTimeHours: Double?
    let weightKg: Double?
    let bmi: Double?
    let bodyFatPercent: Double?
    let muscleMassKg: Double?
    let boneMassKg: Double?
    let bodyWaterPercent: Double?
    let systolicMmHg: Double?
    let diastolicMmHg: Double?
    let bloodPressurePulseBpm: Double?
    let skinTemperatureDeviationC: Double?
    
    enum CodingKeys: String, CodingKey {
        case id
        case athleteId = "athlete_id"
        case entryDate = "entry_date"
        case hrvMs = "hrv_ms"
        case rhrBpm = "rhr_bpm"
        case sleepScore = "sleep_score"
        case readinessScore = "readiness_score"
        case recoveryPhase = "recovery_phase"
        case stressLevel = "stress_level"
        case rawSource = "raw_source"
        case hrvBaselineMs = "hrv_baseline_ms"
        case rhrBaselineBpm = "rhr_baseline_bpm"
        case sleepMinutes = "sleep_minutes"
        case deepSleepMinutes = "deep_sleep_minutes"
        case remSleepMinutes = "rem_sleep_minutes"
        case coreSleepMinutes = "core_sleep_minutes"
        case awakeMinutes = "awake_minutes"
        case sleepStartAt = "sleep_start_at"
        case sleepEndAt = "sleep_end_at"
        case vo2Max = "vo2_max"
        case vo2MaxCycling = "vo2_max_cycling"
        case fitnessAge = "fitness_age"
        case bodyBattery = "body_battery"
        case bodyBatteryHigh = "body_battery_high"
        case bodyBatteryLow = "body_battery_low"
        case bodyBatteryCharged = "body_battery_charged"
        case bodyBatteryDrained = "body_battery_drained"
        case respirationRate = "respiration_rate"
        case spo2Percent = "spo2_percent"
        case hrvStatus = "hrv_status"
        case sleepQualifier = "sleep_qualifier"
        case steps
        case trainingStatus = "training_status"
        case trainingLoad = "training_load"
        case recoveryTimeHours = "recovery_time_hours"
        case weightKg = "weight_kg"
        case bmi
        case bodyFatPercent = "body_fat_percent"
        case muscleMassKg = "muscle_mass_kg"
        case boneMassKg = "bone_mass_kg"
        case bodyWaterPercent = "body_water_percent"
        case systolicMmHg = "systolic_mmhg"
        case diastolicMmHg = "diastolic_mmhg"
        case bloodPressurePulseBpm = "blood_pressure_pulse_bpm"
        case skinTemperatureDeviationC = "skin_temp_deviation_c"
    }
}
