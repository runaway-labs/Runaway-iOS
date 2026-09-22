//
//  ActivityDetailView.swift
//  Runaway iOS
//
//  Created by Jack Rudelic on 6/29/25.
//

import SwiftUI
import MapKit
import CoreLocation
import Combine

struct ActivityDetailView: View {
    let activity: LocalActivity
    @Environment(\.dismiss) private var dismiss
    @Environment(DataManager.self) var dataManager

    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var showContent = false

    // MARK: - Computed Properties

    private var isDistanceBasedActivity: Bool {
        let activityType = activity.type ?? "Run"
        let distanceTypes = ["run", "walk", "ride", "bike", "cycling", "hike", "swim", "virtualrun", "virtualride", "trailrun", "gravel ride", "mountain bike ride"]
        return distanceTypes.contains(activityType.lowercased())
    }

    private var activityType: String {
        activity.type ?? "Workout"
    }

    private var activityIcon: String {
        switch activityType.lowercased() {
        case "run", "virtualrun": return "figure.run"
        case "walk": return "figure.walk"
        case "ride", "bike", "cycling", "virtualride": return "figure.outdoor.cycle"
        case "hike", "trailrun": return "figure.hiking"
        case "swim": return "figure.pool.swim"
        case "yoga": return "figure.mind.and.body"
        case "weight training", "weighttraining", "workout": return "dumbbell.fill"
        case "crossfit": return "figure.cross.training"
        case "elliptical": return "figure.elliptical"
        case "rowing": return "figure.rowing"
        case "rock climbing", "rockclimbing": return "figure.climbing"
        case "alpine ski", "alpineski": return "figure.skiing.downhill"
        case "snowboard": return "figure.snowboarding"
        case "mountain bike ride", "mountainbikeride": return "figure.outdoor.cycle"
        case "gravel ride", "gravelride": return "figure.outdoor.cycle"
        case "golf": return "figure.golf"
        default: return "figure.mixed.cardio"
        }
    }

    private var activityColor: Color {
        AppTheme.Colors.activityColor(for: activityType)
    }

    private var background: Color {
        AppTheme.Colors.adaptiveBackground
    }

    private var cardBackground: Color {
        AppTheme.Colors.adaptiveCardBackground
    }

    private var textPrimary: Color {
        AppTheme.Colors.adaptiveTextPrimary
    }

    private var textSecondary: Color {
        AppTheme.Colors.adaptiveTextSecondary
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            AppTheme.Colors.DarkMode.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // ── Route map ──────────────────────────────────────────
                    if let polyline = activity.summary_polyline, !polyline.isEmpty {
                        ActivityDetailMapView(summaryPolyline: polyline)
                            .frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    // ── Type disc + name + date ────────────────────────────
                    HStack(spacing: 8) {
                        ActivityTypeDisc(activityType: activityType, size: 28, iconSize: 13, cornerRadius: 8)
                        Text(activityType)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(activityColor)

                        Spacer()

                        Menu {
                            Button(role: .destructive) { showDeleteConfirmation = true } label: {
                                Label("Delete Activity", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
                                .frame(width: 36, height: 36)
                                .background(AppTheme.Colors.DarkMode.cardBackground)
                                .clipShape(Circle())
                        }
                        .accessibilityLabel("Activity options")
                    }

                    Text(activity.name ?? "Activity")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    if let startDate = activity.start_date {
                        Text(compactDate(startDate))
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(AppTheme.Colors.DarkMode.textTertiary)
                    }

                    // ── Hero distance / duration ───────────────────────────
                    if isDistanceBasedActivity, let distance = activity.distance {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(UnitFormatter.formatDistance(distance, decimals: 2, includeUnit: false))
                                .font(.system(size: 52, weight: .bold, design: .rounded))
                                .foregroundColor(AppTheme.Colors.warmAmber)
                                .monospacedDigit()
                            Text(UnitFormatter.distanceUnitAbbreviation)
                                .font(.system(size: 18, weight: .medium, design: .rounded))
                                .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
                                .padding(.bottom, 4)
                        }
                    } else if let time = activity.elapsed_time {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(formatTime(seconds: time))
                                .font(.system(size: 52, weight: .bold, design: .rounded))
                                .foregroundColor(AppTheme.Colors.warmAmber)
                                .monospacedDigit()
                            Text("duration")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
                                .padding(.bottom, 4)
                        }
                    }

                    // ── Three mini-stat tiles ──────────────────────────────
                    HStack(spacing: 10) {
                        MiniStatTile(value: formattedElapsed, label: "time")
                        if isDistanceBasedActivity {
                            MiniStatTile(value: formattedPace, label: "/\(UnitFormatter.distanceUnitAbbreviation) pace")
                        } else {
                            MiniStatTile(value: "--", label: "calories")
                        }
                        MiniStatTile(value: "--", label: "bpm avg")
                    }

                    // ── Run insight card ───────────────────────────────────
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(AppTheme.Colors.warmAmber.opacity(0.16))
                                    .frame(width: 32, height: 32)
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(AppTheme.Colors.warmAmber)
                            }
                            EyebrowLabel(text: "RUN INSIGHT", color: AppTheme.Colors.warmAmber)
                        }
                        OnDeviceActivityObservationText(
                            activity: activity,
                            initialObservation: coachInsight
                        )
                    }
                    .padding(14)
                    .background(AppTheme.Colors.warmAmber.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.Colors.warmAmber.opacity(0.18), lineWidth: 1))

                    WorkoutReflectionActivityCard(activity: activity)

                    // ── Splits (empty state) ───────────────────────────────
                    VStack(alignment: .leading, spacing: 10) {
                        EyebrowLabel(text: "SPLITS")
                        Text("Detailed splits not available for this activity")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(AppTheme.Colors.DarkMode.textTertiary)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.Colors.DarkMode.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Spacer(minLength: 32)
                }
                .padding(20)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(AppTheme.Colors.DarkMode.textPrimary)
                        .frame(width: 38, height: 38)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Close activity")
            }
        }
        .alert("Delete Activity", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { deleteActivity() }
        } message: {
            Text("Are you sure you want to delete \"\(activity.name ?? "this activity")\"? This action cannot be undone.")
        }
        .overlay {
            if isDeleting {
                Color.black.opacity(0.4).ignoresSafeArea()
                    .overlay {
                        ProgressView("Deleting...")
                            .padding()
                            .background(AppTheme.Colors.DarkMode.cardBackground)
                            .cornerRadius(12)
                    }
            }
        }
    }

    // MARK: - Computed helpers

    private var formattedElapsed: String {
        guard let t = activity.elapsed_time else { return "--" }
        return formatTime(seconds: t)
    }

    private var formattedPace: String {
        guard let d = activity.distance, let t = activity.elapsed_time, d > 0 else { return "--:--" }
        return UnitFormatter.formatPace(secondsPerMeter: t / d)
    }

    private var coachInsight: String {
        guard let d = activity.distance, let t = activity.elapsed_time, d > 0, t > 0 else {
            return "Great effort on this session — keep building consistency."
        }
        let paceMin = (t / 60) / (d * 0.000621371)
        let mins = Int(paceMin); let secs = Int((paceMin - Double(mins)) * 60)
        return "You averaged \(mins):\(String(format: "%02d", secs))/mi — solid pacing. Keep stacking sessions like this one."
    }

    private func compactDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d · h:mm a"
        return f.string(from: date)
    }

    // MARK: - Helper Methods

    private func deleteActivity() {
        let activityId = activity.id

        isDeleting = true

        Task {
            do {
                try await ActivityService.deleteActivity(id: activityId)

                if let userId = UserSession.shared.userId {
                    await dataManager.loadActivities(for: userId)
                }

                await MainActor.run {
                    isDeleting = false
                    dismiss()
                }
            } catch {
                #if DEBUG
                print("❌ Failed to delete activity: \(error)")
                #endif
                await MainActor.run {
                    isDeleting = false
                }
            }
        }
    }

    private func formatTime(seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatTimeOnly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Activity Detail Map View
struct ActivityDetailMapView: UIViewRepresentable {
    let summaryPolyline: String?

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.overrideUserInterfaceStyle = .dark
        mapView.delegate = context.coordinator
        mapView.isPitchEnabled = false
        mapView.showsCompass = true
        mapView.showsScale = true
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        addRouteToMap(mapView, coordinator: context.coordinator)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, MKMapViewDelegate {
        var startCircle: MKCircle?
        var endCircle: MKCircle?

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor(AppTheme.Colors.accent)
                renderer.lineWidth = 5
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }
            if let circle = overlay as? MKCircle {
                let renderer = MKCircleRenderer(circle: circle)
                renderer.fillColor = (circle === startCircle) ? .systemGreen : .systemRed
                renderer.strokeColor = .white
                renderer.lineWidth = 2
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }

    private func addRouteToMap(_ mapView: MKMapView, coordinator: Coordinator) {
        guard let polylineStr = summaryPolyline else { return }
        let coordinates = decodePolyline(polylineStr)
        guard !coordinates.isEmpty else { return }

        mapView.removeOverlays(mapView.overlays)

        var mutableCoords = coordinates
        mapView.addOverlay(MKPolyline(coordinates: &mutableCoords, count: mutableCoords.count), level: .aboveRoads)

        if coordinates.count >= 2 {
            let start = MKCircle(center: coordinates.first!, radius: 12)
            let end   = MKCircle(center: coordinates.last!,  radius: 12)
            coordinator.startCircle = start
            coordinator.endCircle   = end
            mapView.addOverlay(start, level: .aboveRoads)
            mapView.addOverlay(end,   level: .aboveRoads)
        }

        let lats = coordinates.map(\.latitude), lons = coordinates.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: (maxLat - minLat) * 1.4, longitudeDelta: (maxLon - minLon) * 1.4)
        mapView.setRegion(MKCoordinateRegion(center: center, span: span), animated: false)
    }

    private func decodePolyline(_ encodedPolyline: String) -> [CLLocationCoordinate2D] {
        var unescapedPolyline = encodedPolyline
        for (a, b) in [("\\\\\\\\", "\\\\"), ("\\\\\\", "\\"), ("\\\\", "\\"),
                       ("\\\"", "\""), ("\\'", "'"), ("\\n", "\n"), ("\\r", "\r"),
                       ("\\t", "\t"), ("\\/", "/"), ("\\u0022", "\""), ("\\u0027", "'")] {
            unescapedPolyline = unescapedPolyline.replacingOccurrences(of: a, with: b)
        }
        if unescapedPolyline.hasPrefix("\"") && unescapedPolyline.hasSuffix("\"") {
            unescapedPolyline = String(unescapedPolyline.dropFirst().dropLast())
        }

        var coordinates: [CLLocationCoordinate2D] = []
        let chars = Array(unescapedPolyline)
        var index = 0
        var lat = 0
        var lng = 0

        while index < chars.count {
            // Decode latitude
            var shift = 0
            var result = 0
            var byte: Int

            repeat {
                if index >= chars.count { break }
                byte = Int(chars[index].asciiValue!) - 63
                result |= (byte & 0x1F) << shift
                shift += 5
                index += 1
            } while byte >= 0x20

            let deltaLat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            lat += deltaLat

            // Decode longitude
            shift = 0
            result = 0

            repeat {
                if index >= chars.count { break }
                byte = Int(chars[index].asciiValue!) - 63
                result |= (byte & 0x1F) << shift
                shift += 5
                index += 1
            } while byte >= 0x20

            let deltaLng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            lng += deltaLng

            let coordinate = CLLocationCoordinate2D(
                latitude: Double(lat) / 1e5,
                longitude: Double(lng) / 1e5
            )
            coordinates.append(coordinate)
        }

        return coordinates
    }
}

// MARK: - DateFormatter Extension
extension DateFormatter {
    static let detailFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

#Preview {
    NavigationView {
        ActivityDetailView(activity: LocalActivity(
            id: 1,
            name: "Morning Run",
            type: "Run",
            summary_polyline: "sample_polyline",
            distance: 5000.0,
            start_date: Date(),
            elapsed_time: 1800
        ))
    }
}
