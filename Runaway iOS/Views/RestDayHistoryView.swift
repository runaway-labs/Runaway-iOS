//
//  RestDayHistoryView.swift
//  Runaway iOS
//
//  View for displaying rest day history and recovery status
//

import SwiftUI

struct RestDayHistoryView: View {
    @StateObject private var restDayService = RestDayService.shared
    @State private var restDays: [RestDay] = []
    @State private var summary: RestDaySummary?
    @State private var isLoading = true
    @State private var showMarkRestDaySheet = false

    let athleteId: Int

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Recovery Status Card
                recoveryStatusCard

                // Summary Card
                if let summary = summary {
                    summaryCard(summary)
                }

                // Rest Day List
                restDayListSection

                // Mark Rest Day Button
                markRestDayButton
            }
            .padding()
        }
        .navigationTitle("Rest Days")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadData()
        }
        .refreshable {
            await loadData()
        }
        .sheet(isPresented: $showMarkRestDaySheet) {
            MarkRestDaySheet(athleteId: athleteId) {
                Task {
                    await loadData()
                }
            }
        }
        .tint(AppTheme.Colors.accent)
    }

    // MARK: - Recovery Status Card

    private var recoveryStatusCard: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recovery Status")
                        .font(.headline)
                        .foregroundColor(AppTheme.Colors.textSecondary)

                    Text(restDayService.recoveryStatus.displayName)
                        .font(.title2)
                        .fontWeight(.bold)
                }

                Spacer()

                Image(systemName: restDayService.recoveryStatus.icon)
                    .font(.system(size: 40))
                    .foregroundColor(Color(hex: restDayService.recoveryStatus.color))
            }

            Text(restDayService.recoveryStatus.recommendation)
                .font(.subheadline)
                .foregroundColor(AppTheme.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if restDayService.currentStreak > 0 {
                HStack {
                    Image(systemName: "moon.zzz.fill")
                        .foregroundColor(.blue)
                    Text("Current rest streak: \(restDayService.currentStreak) day\(restDayService.currentStreak == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }

    // MARK: - Summary Card

    private func summaryCard(_ summary: RestDaySummary) -> some View {
        VStack(spacing: 16) {
            Text("Last 30 Days")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 20) {
                statItem(
                    value: "\(summary.totalRestDays)",
                    label: "Rest Days",
                    icon: "moon.zzz.fill"
                )

                statItem(
                    value: String(format: "%.0f%%", summary.restDayPercentage),
                    label: "Rest Rate",
                    icon: "chart.pie.fill"
                )

                statItem(
                    value: "\(summary.longestStreak)",
                    label: "Longest Streak",
                    icon: "flame.fill"
                )
            }

            // Health indicator
            HStack {
                Circle()
                    .fill(summary.isHealthyPattern ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)

                Text(summary.isHealthyPattern
                    ? "Healthy rest pattern (1-2 days/week)"
                    : summary.restDayPercentage < 10
                        ? "Consider more rest days"
                        : "Taking lots of rest - ensure you're training enough"
                )
                .font(.caption)
                .foregroundColor(AppTheme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }

    private func statItem(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)

            Text(value)
                .font(.title2)
                .fontWeight(.bold)

            Text(label)
                .font(.caption)
                .foregroundColor(AppTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Rest Day List

    private var restDayListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Rest Days")
                .font(.headline)

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else if restDays.isEmpty {
                emptyStateView
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(restDays) { restDay in
                        RestDayRow(restDay: restDay)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.run")
                .font(.system(size: 40))
                .foregroundColor(AppTheme.Colors.textSecondary)

            Text("No Rest Days Recorded")
                .font(.headline)

            Text("Days without activities will be automatically logged as rest days.")
                .font(.caption)
                .foregroundColor(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - Mark Rest Day Button

    private var markRestDayButton: some View {
        Button(action: {
            showMarkRestDaySheet = true
        }) {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("Mark Today as Rest Day")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            restDays = try await restDayService.getRestDays(athleteId: athleteId, days: 30)
            summary = try await restDayService.getRestDaySummary(athleteId: athleteId, days: 30)
            await restDayService.refreshData(athleteId: athleteId)
        } catch {
            #if DEBUG
            print("Failed to load rest day data: \(error)")
            #endif
        }
    }
}

// MARK: - Rest Day Row

struct RestDayRow: View {
    let restDay: RestDay

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: restDay.reason.icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 32)

            // Details
            VStack(alignment: .leading, spacing: 2) {
                Text(restDay.reason.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(restDay.shortFormattedDate)
                    .font(.caption)
                    .foregroundColor(AppTheme.Colors.textSecondary)

                if let notes = restDay.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Planned badge
            if restDay.isPlanned {
                Text("Planned")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.2))
                    .foregroundColor(.green)
                    .cornerRadius(4)
            }

            // Recovery benefit
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(restDay.recoveryBenefit)%")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.green)

                Text("recovery")
                    .font(.caption2)
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Mark Rest Day Sheet

struct MarkRestDaySheet: View {
    let athleteId: Int
    let onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedReason: RestDayReason = .scheduled
    @State private var notes: String = ""
    @State private var selectedDate: Date = Date()
    @State private var isSaving = false

    var body: some View {
        NavigationView {
            Form {
                Section("Date") {
                    DatePicker("Rest Day Date", selection: $selectedDate, in: ...Date(), displayedComponents: .date)
                }

                Section("Reason") {
                    ForEach(RestDayReason.allCases.filter { $0 != .detected }, id: \.self) { reason in
                        Button(action: {
                            selectedReason = reason
                        }) {
                            HStack {
                                Image(systemName: reason.icon)
                                    .foregroundColor(.blue)
                                    .frame(width: 24)

                                VStack(alignment: .leading) {
                                    Text(reason.displayName)
                                        .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)
                                }

                                Spacer()

                                if selectedReason == reason {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }

                Section("Notes (Optional)") {
                    TextField("How are you feeling?", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Mark Rest Day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await saveRestDay()
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
        .tint(AppTheme.Colors.accent)
    }

    private func saveRestDay() async {
        isSaving = true
        defer { isSaving = false }

        do {
            try await RestDayService.shared.markAsRestDay(
                athleteId: athleteId,
                date: selectedDate,
                reason: selectedReason,
                notes: notes.isEmpty ? nil : notes
            )
            onComplete()
            dismiss()
        } catch {
            #if DEBUG
            print("Failed to save rest day: \(error)")
            #endif
        }
    }
}

#Preview {
    NavigationView {
        RestDayHistoryView(athleteId: 1)
    }
}
