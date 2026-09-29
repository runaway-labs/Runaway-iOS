import SwiftUI
import MapKit

struct CourseReconView: View {
    let race: AthleteRace
    @State private var course: RaceCourse?
    @State private var isLoading = true
    @State private var selectedMile: Double = 0
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.Colors.DarkMode.background.ignoresSafeArea()
                
                if isLoading {
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(AppTheme.Colors.accent)
                        Text("Analyzing Terrain...")
                            .font(AppTheme.Typography.body)
                            .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
                    }
                } else if let course = course {
                    VStack(spacing: 0) {
                        TacticalMapView(course: course, selectedMile: $selectedMile)
                            .frame(height: 350)
                            .overlay(alignment: .topTrailing) {
                                mileBadge
                            }

                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
                                ElevationChart(course: course, selectedMile: $selectedMile)
                                    .frame(height: 140)
                                    .padding(.top)

                                sectionHeader("RACE STRATEGY")

                                if let insights = course.tacticalInsights, !insights.isEmpty {
                                    ForEach(insights) { insight in
                                        TacticalInsightRow(insight: insight)
                                    }
                                } else {
                                    emptyInsightsCard
                                }
                            }
                            .padding(.bottom, 40)
                        }
                    }
                } else {
                    noCourseState
                }
            }
            .navigationTitle(race.raceName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await loadCourse() }
    }

    private var mileBadge: some View {
        Text("Mile " + String(format: "%.1f", selectedMile))
            .font(.system(size: 14, weight: .bold, design: .monospaced))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.black.opacity(0.75))
            .foregroundColor(.white)
            .cornerRadius(8)
            .padding()
    }

    private var emptyInsightsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "brain.head.profile")
                    .foregroundColor(AppTheme.Colors.accent)
                Text("Analyzing terrain...")
                    .font(AppTheme.Typography.body)
            }
            Text("I'm identifying technical cruxes based on the elevation profile.")
                .font(.system(size: 13))
                .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
        }
        .padding()
        .background(AppTheme.Colors.DarkMode.cardBackground)
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
            .tracking(1.5)
            .padding(.horizontal)
    }

    private var noCourseState: some View {
        VStack(spacing: 20) {
            Image(systemName: "map.fill")
                .font(.system(size: 60))
                .foregroundColor(AppTheme.Colors.accent.opacity(0.5))
            Text("No Course Data Available")
                .font(AppTheme.Typography.headline)
            Text("We couldn't find a spatial map for this race yet.")
                .multilineTextAlignment(.center)
                .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
                .padding(.horizontal, 40)
        }
    }

    private func loadCourse() async {
        guard let raceId = race.runsignupRaceId else {
            isLoading = false
            return
        }
        do {
            course = try await CourseReconService.shared.fetchCourse(
                raceId: raceId,
                eventId: race.eventId ?? 0
            )
        } catch {
            #if DEBUG
            print("❌ CourseRecon: Failed to load: \(error)")
            #endif
        }
        isLoading = false
    }
}

struct TacticalMapView: UIViewRepresentable {
    let course: RaceCourse
    @Binding var selectedMile: Double

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.overrideUserInterfaceStyle = .dark
        mapView.isPitchEnabled = true
        mapView.showsBuildings = true
        mapView.delegate = context.coordinator
        
        if #available(iOS 17.0, *) {
            mapView.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .realistic)
        }

        if let poly = course.polyline {
            let coords = decodePolyline(poly)
            if !coords.isEmpty {
                // Filter out any points that are obviously out of bounds (sanity check for St. Louis area)
                let lats = coords.map { $0.latitude }
                let lons = coords.map { $0.longitude }
                let minLat = lats.min()!, maxLat = lats.max()!
                let minLon = lons.min()!, maxLon = lons.max()!
                
                let centerLat = (minLat + maxLat) / 2
                let centerLon = (minLon + maxLon) / 2
                
                // If a point is more than 0.5 degrees (~35 miles) from center, it's likely a decoding artifact
                let filteredCoords = coords.filter { 
                    abs($0.latitude - centerLat) < 0.5 && abs($0.longitude - centerLon) < 0.5 
                }
                
                if !filteredCoords.isEmpty {
                    var mutableCoords = filteredCoords
                    let overlay = MKPolyline(coordinates: &mutableCoords, count: filteredCoords.count)
                    mapView.addOverlay(overlay)

                    let startPin = MKPointAnnotation()
                    startPin.coordinate = filteredCoords.first!
                    startPin.title = "Start"
                    mapView.addAnnotation(startPin)

                    let finishPin = MKPointAnnotation()
                    finishPin.coordinate = filteredCoords.last!
                    finishPin.title = "Finish"
                    mapView.addAnnotation(finishPin)
                    
                    let fLats = filteredCoords.map { $0.latitude }
                    let fLons = filteredCoords.map { $0.longitude }
                    let region = MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: (fLats.min()! + fLats.max()!) / 2, longitude: (fLons.min()! + fLons.max()!) / 2),
                        span: MKCoordinateSpan(latitudeDelta: (fLats.max()! - fLats.min()!) * 1.4, longitudeDelta: (fLons.max()! - fLons.min()!) * 1.4)
                    )
                    mapView.setRegion(region, animated: false)
                    
                    let camera = MKMapCamera(lookingAtCenter: region.center, fromDistance: 4500, pitch: 65, heading: 0)
                    mapView.setCamera(camera, animated: true)
                }
            }
        }
        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {}
    
    func makeCoordinator() -> Coordinator { Coordinator() }
    class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor(AppTheme.Colors.warmAmber)
                renderer.lineWidth = 4
                renderer.lineCap = .round
                return renderer
            }
            return MKOverlayRenderer()
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let point = annotation as? MKPointAnnotation else { return nil }
            let id = point.title == "Start" ? "StartPin" : "FinishPin"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            view.canShowCallout = true
            if point.title == "Start" {
                view.markerTintColor = UIColor.systemGreen
                view.glyphImage = UIImage(systemName: "flag.fill")
            } else {
                view.markerTintColor = UIColor.systemRed
                view.glyphImage = UIImage(systemName: "flag.checkered")
            }
            return view
        }
    }

    private func decodePolyline(_ encoded: String) -> [CLLocationCoordinate2D] {
        var result: [CLLocationCoordinate2D] = []
        let chars = Array(encoded.unicodeScalars)
        var idx = 0, lat = 0, lng = 0
        while idx < chars.count {
            var shift = 0, res = 0, byte: Int
            repeat {
                guard idx < chars.count else { break }
                byte = Int(chars[idx].value) - 63; idx += 1
                res |= (byte & 0x1F) << shift; shift += 5
            } while byte >= 0x20
            lat += (res & 1) != 0 ? ~(res >> 1) : (res >> 1)
            shift = 0; res = 0
            repeat {
                guard idx < chars.count else { break }
                byte = Int(chars[idx].value) - 63; idx += 1
                res |= (byte & 0x1F) << shift; shift += 5
            } while byte >= 0x20
            lng += (res & 1) != 0 ? ~(res >> 1) : (res >> 1)
            result.append(CLLocationCoordinate2D(latitude: Double(lat) / 1e5, longitude: Double(lng) / 1e5))
        }
        return result
    }
}

struct ElevationChart: View {
    let course: RaceCourse
    @Binding var selectedMile: Double

    private let metersToFeet = 3.28084

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ELEVATION PROFILE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
                    .tracking(1.2)
                Spacer()
                if let data = course.elevationData, !data.isEmpty {
                    let maxFt = Int((data.map { $0.elevation }.max() ?? 0) * metersToFeet)
                    let minFt = Int((data.map { $0.elevation }.min() ?? 0) * metersToFeet)
                    Text("\(minFt)–\(maxFt) ft")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
                }
            }
            .padding(.horizontal)

            if let data = course.elevationData, !data.isEmpty {
                GeometryReader { geo in
                    let elevFt = data.map { $0.elevation * metersToFeet }
                    let minE = elevFt.min() ?? 0
                    let maxE = elevFt.max() ?? 1
                    let range = max(1, maxE - minE)
                    let w = geo.size.width
                    let h = geo.size.height

                    // Build smooth area path
                    let path = Path { p in
                        guard data.count > 1 else { return }
                        let pts: [(CGFloat, CGFloat)] = data.indices.map { i in
                            let x = CGFloat(i) / CGFloat(data.count - 1) * w
                            let y = h - CGFloat((elevFt[i] - minE) / range) * (h - 8)
                            return (x, y)
                        }
                        p.move(to: CGPoint(x: pts[0].0, y: h))
                        p.addLine(to: CGPoint(x: pts[0].0, y: pts[0].1))
                        for i in 1..<pts.count {
                            let prev = pts[i - 1], curr = pts[i]
                            let cx = (prev.0 + curr.0) / 2
                            p.addCurve(to: CGPoint(x: curr.0, y: curr.1),
                                       control1: CGPoint(x: cx, y: prev.1),
                                       control2: CGPoint(x: cx, y: curr.1))
                        }
                        p.addLine(to: CGPoint(x: w, y: h))
                        p.closeSubpath()
                    }

                    let strokePath = Path { p in
                        guard data.count > 1 else { return }
                        let pts: [(CGFloat, CGFloat)] = data.indices.map { i in
                            let x = CGFloat(i) / CGFloat(data.count - 1) * w
                            let y = h - CGFloat((elevFt[i] - minE) / range) * (h - 8)
                            return (x, y)
                        }
                        p.move(to: CGPoint(x: pts[0].0, y: pts[0].1))
                        for i in 1..<pts.count {
                            let prev = pts[i - 1], curr = pts[i]
                            let cx = (prev.0 + curr.0) / 2
                            p.addCurve(to: CGPoint(x: curr.0, y: curr.1),
                                       control1: CGPoint(x: cx, y: prev.1),
                                       control2: CGPoint(x: cx, y: curr.1))
                        }
                    }

                    // Selected mile indicator x position
                    let totalMiles = data.last?.distance ?? 26.2
                    let selX = CGFloat(selectedMile / totalMiles) * w

                    ZStack(alignment: .leading) {
                        path.fill(LinearGradient(
                            colors: [AppTheme.Colors.accent.opacity(0.35), AppTheme.Colors.accent.opacity(0.05)],
                            startPoint: .top, endPoint: .bottom
                        ))
                        strokePath.stroke(AppTheme.Colors.accent, lineWidth: 1.5)

                        // Selected mile vertical line
                        if selectedMile > 0 {
                            Rectangle()
                                .fill(Color.white.opacity(0.5))
                                .frame(width: 1)
                                .offset(x: selX)
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { val in
                        let pct = max(0, min(1, val.location.x / w))
                        let totalMiles = data.last?.distance ?? 26.2
                        selectedMile = pct * totalMiles
                    })
                }
                .padding(.horizontal)
            } else {
                Text("Elevation data unavailable")
                    .font(.caption)
                    .foregroundColor(AppTheme.Colors.DarkMode.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
}

struct TacticalInsightRow: View {
    let insight: TacticalInsight
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack {
                Text("Mile")
                    .font(.system(size: 10, weight: .bold))
                Text(String(format: "%.1f", insight.mile))
                    .font(.system(size: 16, weight: .heavy, design: .monospaced))
            }
            .foregroundColor(AppTheme.Colors.accent)
            .frame(width: 50)

            VStack(alignment: .leading, spacing: 4) {
                Text(insight.description)
                    .font(AppTheme.Typography.body)
                    .foregroundColor(AppTheme.Colors.DarkMode.textPrimary)
            }
        }
        .padding()
        .background(AppTheme.Colors.DarkMode.cardBackground)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.07), lineWidth: 1))
        .padding(.horizontal)
    }
}
