//
//  CoachSettingsView.swift
//  Runaway iOS
//
//  Created by Claude on 12/23/25.
//

import SwiftUI

// MARK: - Coach Settings View

struct CoachSettingsView: View {

    @StateObject private var store = CoachSettingsStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                // Master toggle
                Section {
                    Toggle("Audio Coaching", isOn: $store.settings.isEnabled)
                } footer: {
                    Text("Enable voice prompts during your runs.")
                }

                // Split announcements
                Section("Split Announcements") {
                    Toggle("Announce Splits", isOn: $store.settings.announceSplits)

                    if store.settings.announceSplits {
                        Picker("Detail Level", selection: $store.settings.splitDetail) {
                            ForEach(SplitDetail.allCases, id: \.self) { detail in
                                Text(detail.displayName).tag(detail)
                            }
                        }
                    }
                }

                // Pace alerts
                Section {
                    Toggle("Pace Drift Alerts", isOn: $store.settings.paceAlerts)

                    if store.settings.paceAlerts {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Alert Threshold: \(Int(store.settings.paceDriftThreshold * 100))%")
                                .font(.subheadline)

                            Slider(
                                value: $store.settings.paceDriftThreshold,
                                in: 0.05...0.25,
                                step: 0.05
                            )
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Pace Alerts")
                } footer: {
                    Text("Alert when your pace deviates from target or average.")
                }

                // Heart rate zone alerts
                Section {
                    Toggle("Zone Transition Alerts", isOn: $store.settings.zoneAlerts)

                    if store.settings.zoneAlerts {
                        NavigationLink("Configure Max Heart Rate") {
                            MaxHeartRateSettingsView()
                        }
                    }
                } header: {
                    Text("Heart Rate Zones")
                } footer: {
                    Text("Get notified when entering or leaving heart rate zones.")
                }

                // Check-ins
                Section {
                    Toggle("Periodic Check-Ins", isOn: $store.settings.enableCheckIns)

                    if store.settings.enableCheckIns {
                        Picker("Check-In Interval", selection: $store.settings.checkInInterval) {
                            Text("3 minutes").tag(TimeInterval(180))
                            Text("5 minutes").tag(TimeInterval(300))
                            Text("10 minutes").tag(TimeInterval(600))
                            Text("15 minutes").tag(TimeInterval(900))
                        }

                        Toggle("Smart Timing", isOn: $store.settings.smartCheckInTiming)
                    }
                } header: {
                    Text("Check-Ins")
                } footer: {
                    if store.settings.enableCheckIns && store.settings.smartCheckInTiming {
                        Text("Smart timing avoids interrupting during intense efforts.")
                    } else {
                        Text("Ask how you're feeling during your run.")
                    }
                }

                // Voice settings
                Section("Voice") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Speech Rate")
                            .font(.subheadline)

                        HStack {
                            Text("Slow")
                                .font(.caption)
                                .foregroundColor(AppTheme.Colors.textSecondary)

                            Slider(
                                value: $store.settings.speechRate,
                                in: 0.35...0.65,
                                step: 0.05
                            )

                            Text("Fast")
                                .font(.caption)
                                .foregroundColor(AppTheme.Colors.textSecondary)
                        }
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Volume")
                            .font(.subheadline)

                        HStack {
                            Image(systemName: "speaker.fill")
                                .font(.caption)
                                .foregroundColor(AppTheme.Colors.textSecondary)

                            Slider(
                                value: $store.settings.volume,
                                in: 0.5...1.0,
                                step: 0.1
                            )

                            Image(systemName: "speaker.wave.3.fill")
                                .font(.caption)
                                .foregroundColor(AppTheme.Colors.textSecondary)
                        }
                    }
                    .padding(.vertical, 4)

                    Toggle("Duck Music Volume", isOn: $store.settings.duckMusicDuringPrompts)
                }

                // Voice input
                Section {
                    Toggle("Voice Input", isOn: $store.settings.enableVoiceInput)

                    if store.settings.enableVoiceInput {
                        Toggle("Auto-Listen After Check-Ins", isOn: $store.settings.autoListenAfterCheckIn)

                        Toggle("Shake to Speak", isOn: $store.settings.enableShakeToSpeak)
                    }
                } header: {
                    Text("Voice Input")
                } footer: {
                    if store.settings.enableVoiceInput {
                        if store.settings.autoListenAfterCheckIn {
                            Text("Will automatically listen for your response after asking \"How are you feeling?\"")
                        } else {
                            Text("Use the microphone button to respond to check-ins.")
                        }
                    } else {
                        Text("Enable to use voice commands and respond to check-ins.")
                    }
                }

                // Target pace
                Section {
                    Toggle("Set Target Pace", isOn: Binding(
                        get: { store.settings.targetPace != nil },
                        set: { enabled in
                            if enabled {
                                store.settings.targetPace = 480 // 8:00/mi default
                            } else {
                                store.settings.targetPace = nil
                            }
                        }
                    ))

                    if let pace = store.settings.targetPace {
                        TargetPacePicker(targetPace: Binding(
                            get: { pace },
                            set: { store.settings.targetPace = $0 }
                        ))
                    }
                } header: {
                    Text("Target Pace")
                } footer: {
                    Text("Pace drift alerts will compare against target when set.")
                }

                // Distance unit
                Section("Units") {
                    Picker("Distance Unit", selection: $store.settings.distanceUnit) {
                        Text("Miles").tag(DistanceUnit.miles)
                        Text("Kilometers").tag(DistanceUnit.kilometers)
                    }
                }
            }
            .navigationTitle("Audio Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Target Pace Picker

private struct TargetPacePicker: View {
    @Binding var targetPace: TimeInterval

    var body: some View {
        HStack {
            Text("Target")
            Spacer()
            HStack(spacing: 4) {
                Picker("Minutes", selection: Binding(
                    get: { Int(targetPace) / 60 },
                    set: { targetPace = TimeInterval($0 * 60 + Int(targetPace) % 60) }
                )) {
                    ForEach(4..<16) { min in
                        Text("\(min)").tag(min)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 50)
                .clipped()

                Text(":")

                Picker("Seconds", selection: Binding(
                    get: { Int(targetPace) % 60 },
                    set: { targetPace = TimeInterval((Int(targetPace) / 60) * 60 + $0) }
                )) {
                    ForEach(0..<60) { sec in
                        Text(String(format: "%02d", sec)).tag(sec)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 50)
                .clipped()

                Text("/mi")
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
        }
        .frame(height: 100)
    }
}

// MARK: - Max Heart Rate Settings

private struct MaxHeartRateSettingsView: View {
    @StateObject private var store = CoachSettingsStore.shared
    @State private var age: Int = 30
    @State private var useEstimated: Bool = true

    var estimatedMaxHR: Int {
        220 - age
    }

    var body: some View {
        Form {
            Section {
                Toggle("Use Estimated Max HR", isOn: $useEstimated)
            } footer: {
                Text("Estimated max HR = 220 - age")
            }

            if useEstimated {
                Section("Your Age") {
                    Stepper("\(age) years old", value: $age, in: 15...85)
                }

                Section {
                    HStack {
                        Text("Estimated Max HR")
                        Spacer()
                        Text("\(estimatedMaxHR) bpm")
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }
                }
            } else {
                Section("Custom Max HR") {
                    Stepper("\(store.settings.maxHeartRate ?? 180) bpm",
                            value: Binding(
                                get: { store.settings.maxHeartRate ?? 180 },
                                set: { store.settings.maxHeartRate = $0 }
                            ),
                            in: 140...220)
                }
            }

            Section {
                HStack {
                    Text("Resting HR (optional)")
                    Spacer()
                    TextField("60", value: $store.settings.restingHeartRate, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                    Text("bpm")
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
            } footer: {
                Text("For more accurate zone calculations using heart rate reserve.")
            }
        }
        .navigationTitle("Heart Rate Zones")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let maxHR = store.settings.maxHeartRate {
                age = 220 - maxHR
                useEstimated = false
            }
        }
        .onChange(of: age) { _, newAge in
            if useEstimated {
                store.settings.maxHeartRate = 220 - newAge
            }
        }
        .onChange(of: useEstimated) { _, estimated in
            if estimated {
                store.settings.maxHeartRate = 220 - age
            }
        }
    }
}

// MARK: - Preview

#Preview {
    CoachSettingsView()
}
