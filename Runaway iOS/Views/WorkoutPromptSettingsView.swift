import SwiftUI

struct WorkoutPromptSettingsView: View {
    let athleteID: Int
    @Environment(\.dismiss) private var dismiss
    @State private var draft: WorkoutPromptSettings?
    @State private var error: String?
    @State private var saving = false
    @State private var schedules: [WorkoutPromptSchedule] = []

    private var validationMessage: String? {
        guard var value = draft else { return nil }
        value.schedules = schedules
        return value.scheduleValidationMessage
    }

    var body: some View {
        NavigationStack {
            Form {
                if let value = draft {
                    Section {
                        Toggle("Workout recommendations", isOn: Binding(get: { draft?.enabled ?? false }, set: { draft?.enabled = $0 }))
                        Text("A timely nudge toward the run, strength session, or recovery day in your training mix. Generation stays on your device; Runaway delivers the notification.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if value.enabled {
                        ForEach($schedules) { $schedule in
                            Section {
                                DatePicker("Notification time", selection: $schedule.time, displayedComponents: .hourAndMinute)
                                DisclosureGroup("Days: " + daySummary(schedule.weekdays)) {
                                    ForEach(1...7, id: \.self) { day in
                                        Toggle(Calendar.current.weekdaySymbols[day - 1], isOn: Binding(
                                            get: { schedule.weekdays.contains(day) },
                                            set: { selected in
                                                if selected { schedule.weekdays = Array(Set(schedule.weekdays + [day])).sorted() }
                                                else { schedule.weekdays.removeAll { $0 == day } }
                                            }))
                                    }
                                }
                                Button("Remove time", role: .destructive) {
                                    schedules.removeAll { $0.id == schedule.id }
                                }.disabled(schedules.count == 1)
                            }
                        }
                        Section {
                            Button("Add time", systemImage: "plus") {
                                let occupied = Set(schedules.map { $0.hour * 60 + $0.minute })
                                let next = (0..<24).map { ($0 + 12) % 24 * 60 }
                                    .first { !occupied.contains($0) } ?? 720
                                schedules.append(WorkoutPromptSchedule(hour: next / 60, minute: next % 60))
                            }.disabled(schedules.count >= 12)
                            if let validationMessage { Text(validationMessage).font(.footnote).foregroundStyle(.red) }
                            Text("Choose up to 12 times, each with its own days. Each check-in uses your latest synced plan; completed sessions are skipped when that information is current.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Section("Time zone") {
                            TextField("Time zone", text: Binding(get: { draft?.timezone ?? "" }, set: { draft?.timezone = $0 }))
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                            Button("Use current time zone") { draft?.timezone = TimeZone.current.identifier }
                            Text("Times stay in this time zone when you travel. Delivery can be delayed by connectivity or iPhone notification settings.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Section("Privacy") {
                            Toggle("Show workout name on Lock Screen", isOn: Binding(
                                get: { draft?.show_workout_name ?? false }, set: { draft?.show_workout_name = $0 }))
                            Text("Off keeps the notification general. Your goals, recovery metrics, and workout notes never appear in notification text.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Section("Keep recommendations current") {
                            Text("Open Runaway after workouts or plan changes. If its saved recommendation is missing or older than 36 hours, you'll get a refresh prompt instead of outdated training advice.")
                                .font(.footnote)
                            if let syncError = WorkoutPromptService.shared.syncError { Text(syncError).foregroundStyle(.orange) }
                            Text(PushNotificationService.shared.settingsSummary).font(.footnote)
                            Button("iPhone notification permissions") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                            }
                        }
                    }
                } else { ProgressView("Loading your preferences") }
                if let error { Section { Text(error).foregroundStyle(.red); Button("Retry") { Task { await load() } } } }
            }
            .navigationTitle("Workout notifications")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving..." : "Save") { Task { await save() } }
                        .disabled(draft == nil || saving || validationMessage != nil)
                }
            }
            .disabled(saving)
            .task { await load() }
        }
    }

    private func load() async {
        do {
            try await WorkoutPromptService.shared.load(athleteID: athleteID)
            draft = WorkoutPromptService.shared.settings
            schedules = draft?.effectiveSchedules ?? []
            error = nil
        } catch { self.error = "Couldn't load notification preferences. Please try again." }
    }

    private func save() async {
        guard var draft else { return }
        saving = true
        defer { saving = false }
        draft.schedules = schedules
        do { try await WorkoutPromptService.shared.save(draft); dismiss() }
        catch { self.error = error.localizedDescription }
    }

    private func daySummary(_ days: [Int]) -> String {
        let days = Array(Set(days)).sorted()
        if days == Array(1...7) { return "Every day" }
        if days.isEmpty { return "Choose days" }
        return days.filter { (1...7).contains($0) }
            .map { Calendar.current.shortWeekdaySymbols[$0 - 1] }.joined(separator: ", ")
    }
}

struct WorkoutPromptDeliveryView: View {
    let route: WorkoutPromptRoute
    let openToday: () -> Void
    @State private var delivery: WorkoutPromptDelivery?
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        Group {
            if let delivery, delivery.fresh == true, delivery.is_today, !delivery.completed, let content = delivery.content {
                WorkoutDetailSheet(workout: content.workout, whyToday: content.whyToday, recommendationOnly: content.recommendationOnly)
                    .safeAreaInset(edge: .top) {
                        if let sent = delivery.sent_revision, sent != delivery.revision {
                            Text("Your plan changed. These are the latest details.").font(.footnote).padding()
                        }
                    }
            } else {
                NavigationStack {
                    VStack(spacing: 18) {
                        if loading { ProgressView("Opening your recommendation") }
                        else {
                            Image(systemName: "calendar.badge.clock").font(.largeTitle)
                            Text(delivery?.completed == true && delivery?.fresh == true ? "Session already completed" : "Let's check today's plan")
                                .font(.title2.bold())
                            Text(error ?? "This notification may be from an earlier day, or your training has changed. Open Today for a current recommendation.")
                                .foregroundStyle(.secondary).multilineTextAlignment(.center)
                            Button("Open Today", action: openToday).buttonStyle(.borderedProminent)
                        }
                    }.padding()
                }
            }
        }
        .task {
            do {
                guard UserSession.shared.userId == route.athleteID else { loading = false; return }
                delivery = try await WorkoutPromptService.shared.delivery(route.id)
            } catch { self.error = "Couldn't load this recommendation. You can still review your plan in Today." }
            loading = false
        }
    }
}
