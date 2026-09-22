import Foundation

struct LocalDate: Codable, Equatable, Hashable, CustomStringConvertible {
    let value: String
    init(_ value: String) { self.value = value }
    var description: String { value }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        guard AthleteTrainingGoal.isValidLocalDate(value) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid local date"))
        }
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

enum RecoveryDirection: String, Codable { case supportive, neutral, caution, protective }
enum IntensityCap: String, Codable { case maintain, reduceOne = "reduce_one", reduceTwo = "reduce_two", recoveryOnly = "recovery_only" }
enum EvidenceConfidence: String, Codable { case low, medium, high }
enum PrescriptionStatus: String, Codable { case shadow, published, superseded }

struct AthleteStateReason: Codable, Equatable, Identifiable {
    let signal: String
    let classification: String
    let score: Double?
    let reason: String
    var id: String { signal + ":" + reason }
}

struct AthleteStateSnapshot: Codable, Equatable {
    let id: UUID
    let stateDate: LocalDate
    let policyVersion: String
    let inputFingerprint: String
    let fitnessLoad: Double
    let fatigueLoad: Double
    let trainingBalance: Double
    let recoveryDirection: RecoveryDirection
    let intensityCap: IntensityCap
    let confidence: EvidenceConfidence
    let reasons: [AthleteStateReason]
    let missingSignals: [String]
    let sourceCoverage: [String: String]
    let calculatedAt: Date

    init(id: UUID, stateDate: LocalDate, policyVersion: String, inputFingerprint: String,
         fitnessLoad: Double, fatigueLoad: Double, trainingBalance: Double,
         recoveryDirection: RecoveryDirection, intensityCap: IntensityCap,
         confidence: EvidenceConfidence, reasons: [AthleteStateReason],
         missingSignals: [String] = [], sourceCoverage: [String: String], calculatedAt: Date) {
        self.id = id; self.stateDate = stateDate; self.policyVersion = policyVersion
        self.inputFingerprint = inputFingerprint; self.fitnessLoad = fitnessLoad
        self.fatigueLoad = fatigueLoad; self.trainingBalance = trainingBalance
        self.recoveryDirection = recoveryDirection; self.intensityCap = intensityCap
        self.confidence = confidence; self.reasons = reasons; self.missingSignals = missingSignals
        self.sourceCoverage = sourceCoverage; self.calculatedAt = calculatedAt
    }

    func isStale(reference: Date = Date(), maximumAge: TimeInterval = 24 * 3_600) -> Bool {
        reference.timeIntervalSince(calculatedAt) > maximumAge
    }

    private enum CodingKeys: String, CodingKey {
        case id, reasons, confidence, missingSignals
        case stateDate = "state_date", policyVersion = "policy_version"
        case inputFingerprint = "input_fingerprint", fitnessLoad = "fitness_load"
        case fatigueLoad = "fatigue_load", trainingBalance = "training_balance"
        case recoveryDirection = "recovery_direction", intensityCap = "intensity_cap"
        case sourceCoverage = "source_coverage", calculatedAt = "calculated_at"
    }
    private struct ReasonEnvelope: Codable {
        let contributing: [AthleteStateReason]?
        let missing: [String]?
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        stateDate = try values.decode(LocalDate.self, forKey: .stateDate)
        policyVersion = try values.decode(String.self, forKey: .policyVersion)
        inputFingerprint = try values.decode(String.self, forKey: .inputFingerprint)
        fitnessLoad = try values.decode(Double.self, forKey: .fitnessLoad)
        fatigueLoad = try values.decode(Double.self, forKey: .fatigueLoad)
        trainingBalance = try values.decode(Double.self, forKey: .trainingBalance)
        recoveryDirection = try values.decode(RecoveryDirection.self, forKey: .recoveryDirection)
        intensityCap = try values.decode(IntensityCap.self, forKey: .intensityCap)
        confidence = try values.decode(EvidenceConfidence.self, forKey: .confidence)
        if let envelope = try? values.decode(ReasonEnvelope.self, forKey: .reasons) {
            reasons = envelope.contributing ?? []
            missingSignals = envelope.missing ?? []
        } else {
            reasons = try values.decode([AthleteStateReason].self, forKey: .reasons)
            missingSignals = try values.decodeIfPresent([String].self, forKey: .missingSignals) ?? []
        }
        sourceCoverage = try values.decode([String: String].self, forKey: .sourceCoverage)
        calculatedAt = try values.decode(Date.self, forKey: .calculatedAt)
    }
}

struct SessionPrescriptionSnapshot: Codable, Equatable {
    let kind: String
    let durationSeconds: Int
    let intensity: String
}

struct DatedPrescriptionSnapshot: Codable, Equatable {
    let date: LocalDate
    let prescription: SessionPrescriptionSnapshot
}

struct PrescriptionReasonSnapshot: Codable, Equatable, Identifiable {
    let code: String
    let detail: String
    var id: String { code }
}

struct TrainingPrescriptionRevision: Codable, Equatable {
    let id: UUID
    let prescriptionDate: LocalDate
    let policyVersion: String
    let inputFingerprint: String
    let status: PrescriptionStatus
    let prescription: SessionPrescriptionSnapshot
    let remainingWeek: [DatedPrescriptionSnapshot]
    let reasons: [PrescriptionReasonSnapshot]
    let confidence: EvidenceConfidence
    let calculatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, status, prescription, reasons, confidence
        case prescriptionDate = "prescription_date", policyVersion = "policy_version"
        case inputFingerprint = "input_fingerprint", remainingWeek = "remaining_week"
        case calculatedAt = "calculated_at"
    }
}
