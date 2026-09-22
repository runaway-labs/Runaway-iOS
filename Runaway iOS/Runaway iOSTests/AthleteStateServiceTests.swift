import XCTest
@testable import Runaway_iOS

@MainActor
final class AthleteStateServiceTests: XCTestCase {
    func testDecodesGarminExtendedBiometricsWithoutRounding() throws {
        let fixture = Data(#"""
        {
          "athlete_id":1,"entry_date":"2026-09-22","hrv_ms":29.125,
          "vo2_max":46.7,"vo2_max_cycling":48.25,"fitness_age":31.5,
          "body_battery":73,"body_battery_high":91.5,"body_battery_low":18.25,
          "body_battery_charged":54.75,"body_battery_drained":17.5,
          "respiration_rate":14.25,"spo2_percent":97.75,"hrv_status":"BALANCED",
          "sleep_qualifier":"GOOD","steps":12345,"training_status":"PRODUCTIVE",
          "training_load":612.375,"recovery_time_hours":19.5,"weight_kg":82.625,
          "bmi":24.875,"body_fat_percent":16.125,"muscle_mass_kg":65.375,
          "bone_mass_kg":3.625,"body_water_percent":58.875,"systolic_mmhg":118.5,
          "diastolic_mmhg":76.25,"blood_pressure_pulse_bpm":52.75,
          "skin_temp_deviation_c":-0.375
        }
        """#.utf8)

        let metric = try SupabaseDecoder.shared.decode(AthleteBiometric.self, from: fixture)

        XCTAssertEqual(metric.hrvMs!, 29.125, accuracy: 0.0001)
        XCTAssertEqual(metric.vo2Max!, 46.7, accuracy: 0.0001)
        XCTAssertEqual(metric.bodyBattery!, 73, accuracy: 0.0001)
        XCTAssertEqual(metric.skinTemperatureDeviationC!, -0.375, accuracy: 0.0001)
    }

    func testSnapshotOlderThanPolicyWindowIsStale() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        XCTAssertTrue(snapshot(calculatedAt: now.addingTimeInterval(-25 * 3_600))
            .isStale(reference: now, maximumAge: 24 * 3_600))
        XCTAssertFalse(snapshot(calculatedAt: now.addingTimeInterval(-23 * 3_600))
            .isStale(reference: now, maximumAge: 24 * 3_600))
    }

    func testFailedRefreshPreservesLastKnownGoodSnapshot() async throws {
        let expected = snapshot(calculatedAt: Date())
        var attempts = 0
        let service = AthleteStateService(stateLoader: { _ in
            attempts += 1
            if attempts == 1 { return expected }
            throw URLError(.notConnectedToInternet)
        }, prescriptionLoader: { _, _ in nil })

        try await service.refresh(athleteID: 1)
        do { try await service.refresh(athleteID: 1); XCTFail("Expected refresh failure") } catch { }

        XCTAssertEqual(service.snapshot, expected)
        XCTAssertNotNil(service.refreshError)
    }

    private func snapshot(calculatedAt: Date) -> AthleteStateSnapshot {
        AthleteStateSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            stateDate: LocalDate("2026-09-22"), policyVersion: "athlete-state-v1",
            inputFingerprint: "fingerprint", fitnessLoad: 35.125, fatigueLoad: 30.75,
            trainingBalance: 4.375, recoveryDirection: .neutral, intensityCap: .maintain,
            confidence: .high, reasons: [], sourceCoverage: ["hrv": "garmin"],
            calculatedAt: calculatedAt
        )
    }
}

extension AthleteStateServiceTests {
    func testPersistedSnapshotRoundTripsThroughCacheEncoding() throws {
        let snapshot = AthleteStateSnapshot(
            id: UUID(),
            stateDate: LocalDate("2026-09-22"),
            policyVersion: "athlete-state-v1",
            inputFingerprint: "fixture",
            fitnessLoad: 31.25,
            fatigueLoad: 18.75,
            trainingBalance: 12.5,
            recoveryDirection: .neutral,
            intensityCap: .maintain,
            confidence: .high,
            reasons: [AthleteStateReason(
                signal: "training_balance",
                classification: "balanced",
                score: 12.5,
                reason: "Load is balanced."
            )],
            missingSignals: ["hrv"],
            sourceCoverage: ["garmin": "2026-09-22T12:00:00Z"],
            calculatedAt: Date(timeIntervalSince1970: 1_790_077_200)
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(AthleteStateSnapshot.self, from: data)

        XCTAssertEqual(decoded.reasons, snapshot.reasons)
        XCTAssertEqual(decoded.missingSignals, snapshot.missingSignals)
    }
}
