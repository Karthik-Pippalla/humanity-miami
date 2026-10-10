import ActivityKit
import CoreLocation
import Foundation
import MapKit
import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class TripStore: NSObject, CLLocationManagerDelegate {
    static let shared = TripStore()

    var origin: Place?
    var destination: Place?
    var depart = Date()
    var trip: Trip?
    var selectedId: String?
    var explanation: Explanation?
    var explainGaps: [String] = []
    var loading = false
    var explaining = false
    var errorMessage: String?
    var camera: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 25.78, longitude: -80.2),
            span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.45)
        )
    )
    var navigation: ActiveNavigation?
    /// Heading of the map viewpoint, used to aim the navigation arrow.
    var mapHeading: CLLocationDirection = 0
    var featureMode: FeatureMode = .drive
    var language = "en"
    var dayPlan: DayPlan?
    var here: Place?

    private let location = CLLocationManager()
    private let api = APIClient()
    private let speaker = GuidanceSpeaker()
    private var requestGeneration = 0
    private var explainGeneration = 0
    private var locationMode: LocationMode = .idle
    private var compassHeading: CLLocationDirection = -1
    private var lastLocation: CLLocation?
    private var offRouteSince: Date?
    private var lastRerouteAt: Date?
    private var rerouteTask: Task<Void, Never>?
    private var followCamera: MapCamera?
    private var lastAppliedHeading: CLLocationDirection = -1
    private var correctingViewpoint = false

    override init() {
        super.init()
        location.delegate = self
    }

    func restoreHandoff() {
        guard trip == nil, let saved = TripHandoff.load() else { return }
        show(
            saved,
            fetchedExplanation: Explanation(text: ScoreNote.text(for: saved), model: "route-scores", basedOn: "route_facts"),
            requestExplanation: false
        )
    }

    func useCurrentLocation() {
        locationMode = .origin
        location.requestWhenInUseAuthorization()
        location.requestLocation()
    }

    func sampleLocation() {
        locationMode = .sample
        location.requestWhenInUseAuthorization()
        location.requestLocation()
    }

    func reexplain() async {
        guard let trip else { return }
        explainGeneration += 1
        await explain(trip, generation: explainGeneration)
    }

    func showPlan(_ plan: DayPlan) {
        dayPlan = plan
        featureMode = .plan
        let points = plan.geometry.coordinates.compactMap { pair -> (latitude: Double, longitude: Double)? in
            guard pair.count >= 2 else { return nil }
            return (latitude: pair[1], longitude: pair[0])
        }
        fit(points)
    }

    func loadDemo() {
        origin = DemoTrip.origin
        destination = DemoTrip.destination
        Task { await compare() }
    }

    func compare() async {
        guard let origin, let destination else {
            errorMessage = "Choose an origin and a destination in South Florida."
            return
        }
        await compare(origin: origin, destination: destination, departAt: depart)
    }

    func show(_ trip: Trip, fetchedExplanation: Explanation? = nil, requestExplanation: Bool = true, adjustCamera: Bool = true) {
        origin = trip.origin
        destination = trip.destination
        self.trip = trip
        selectedId = trip.recommendedId
        explanation = fetchedExplanation
        explainGaps = []
        errorMessage = nil
        if adjustCamera {
            fit(trip)
        }
        focusSelectedRoute()
        LiveActivityController.start(trip)
        CarPlayCoordinator.shared.refresh(with: trip, selectedId: trip.recommendedId)
        Task { await SpotlightIndexer.index(trip) }
        explainGeneration += 1
        if requestExplanation, fetchedExplanation == nil {
            let generation = explainGeneration
            Task { await explain(trip, generation: generation) }
        }
    }

    func select(_ id: String, updateCarPlay: Bool = true) {
        selectedId = id
        focusSelectedRoute()
        if updateCarPlay, let trip {
            CarPlayCoordinator.shared.refresh(with: trip, selectedId: id)
        }
    }

    func selectRoute(near coordinate: CLLocationCoordinate2D) {
        guard navigation == nil, let trip else { return }
        var best: (id: String, distance: Double)?
        for route in trip.routes {
            let snapshot = RouteGuidance.evaluate(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                coordinates: route.coordinates,
                maneuvers: route.maneuvers ?? [],
                durationSeconds: route.durationSeconds
            )
            if best == nil || snapshot.distanceFromLineMeters < best!.distance {
                best = (route.id, snapshot.distanceFromLineMeters)
            }
        }
        if let best, best.distance <= 150 {
            select(best.id)
        }
    }

    func startNavigation(routeId: String) {
        guard let trip, trip.routes.contains(where: { $0.id == routeId }) else { return }
        select(routeId)
        speaker.reset()
        offRouteSince = nil
        rerouteTask?.cancel()
        let route = trip.routes.first { $0.id == routeId }
        let bearing = RouteGuidance.bearing(along: route?.coordinates ?? [])
        let status = location.authorizationStatus
        var session = ActiveNavigation(
            routeId: routeId,
            snapshot: nil,
            heading: bearing,
            rerouting: false,
            locationProblem: status == .denied || status == .restricted
                ? "Location access is off. Allow location to guide this drive."
                : nil,
            followsUser: true,
            userLatitude: lastLocation?.coordinate.latitude ?? route?.coordinates.first?.latitude,
            userLongitude: lastLocation?.coordinate.longitude ?? route?.coordinates.first?.longitude
        )
        navigation = session
        locationMode = .guidance
        location.requestWhenInUseAuthorization()
        location.activityType = .automotiveNavigation
        location.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        location.distanceFilter = 5
        location.headingFilter = 12
        location.startUpdatingLocation()
        location.startUpdatingHeading()
        UIApplication.shared.isIdleTimerDisabled = true
        if let lastLocation {
            let heading = travelHeading(for: lastLocation)
            session.heading = heading
            navigation = session
            follow(lastLocation, heading: heading)
        } else if let start = route?.coordinates.first {
            follow(CLLocation(latitude: start.latitude, longitude: start.longitude), heading: bearing)
        }
    }

    func noteMapHeading(_ heading: CLLocationDirection) {
        guard navigation?.followsUser == false else { return }
        mapHeading = heading
    }

    func pauseFollow() {
        guard navigation?.followsUser == true else { return }
        navigation?.followsUser = false
    }

    func resumeFollow() {
        guard var session = navigation else { return }
        session.followsUser = true
        navigation = session
        guard let lastLocation else { return }
        follow(lastLocation, heading: session.heading)
    }

    /// Drops map-driven viewpoint changes while guidance is following, so a flat region cannot replace the tilted view.
    func adoptMapPosition(_ position: MapCameraPosition) {
        guard navigation?.followsUser == true else {
            camera = position
            return
        }
        guard !correctingViewpoint else { return }
        guard let followCamera else { return }
        if position == .camera(followCamera) { return }
        correctingViewpoint = true
        camera = .camera(followCamera)
        correctingViewpoint = false
    }

    func endNavigation() {
        navigation = nil
        locationMode = .idle
        location.stopUpdatingLocation()
        location.stopUpdatingHeading()
        location.distanceFilter = kCLDistanceFilterNone
        location.desiredAccuracy = kCLLocationAccuracyBest
        location.activityType = .other
        UIApplication.shared.isIdleTimerDisabled = false
        speaker.reset()
        offRouteSince = nil
        rerouteTask?.cancel()
        if let trip {
            fit(trip)
        }
    }

    private func compare(origin: Place, destination: Place, departAt: Date) async {
        let generation = requestGeneration + 1
        requestGeneration = generation
        loading = true
        explaining = false
        errorMessage = nil
        explanation = nil
        explainGaps = []
        do {
            let trip = try await api.routes(origin: origin, destination: destination, departAt: departAt)
            guard requestGeneration == generation else { return }
            show(trip)
            loading = false
        } catch let error as APIError {
            guard requestGeneration == generation else { return }
            self.trip = nil
            errorMessage = error.message
            loading = false
        } catch {
            guard requestGeneration == generation else { return }
            self.trip = nil
            errorMessage = "Could not plan a route."
            loading = false
        }
    }

    private func explain(_ trip: Trip, generation: Int) async {
        explaining = true
        do {
            let note = try await api.explain(facts: trip.explanationFacts, language: language)
            guard generation == explainGeneration else { return }
            explanation = note.explanation
            explainGaps = note.dataGaps
        } catch {
            guard generation == explainGeneration else { return }
            explanation = Explanation(text: ScoreNote.text(for: trip), model: "route-scores", basedOn: "route_facts")
            explainGaps = ["gemini_unavailable"]
        }
        if generation == explainGeneration {
            explaining = false
        }
    }

    private func fit(_ trip: Trip) {
        fit(trip.routes.flatMap(\.coordinates))
    }

    private func fit(_ points: [(latitude: Double, longitude: Double)]) {
        guard !points.isEmpty else { return }
        var rect = MKMapRect.null
        for point in points {
            let mapPoint = MKMapPoint(CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
            rect = rect.union(MKMapRect(origin: mapPoint, size: MKMapSize(width: 0, height: 0)))
        }
        if rect.isNull { return }
        var fitted = rect
        if fitted.size.width < 2000 { fitted.size.width = 2000 }
        if fitted.size.height < 2000 { fitted.size.height = 2000 }
        let padded = fitted.insetBy(dx: -fitted.size.width * 0.2, dy: -fitted.size.height * 0.2)
        camera = .rect(padded)
    }

    private func focusSelectedRoute() {
        guard let trip, let route = trip.routes.first(where: { $0.id == selectedId }) ?? trip.recommended else { return }
        OnScreenRoutes.focus(
            AnnotatedRoute(
                id: route.id,
                label: route.label,
                summary: route.flood.summary,
                minutes: RouteFormat.minutes(route.durationSeconds),
                recommended: route.id == trip.recommendedId
            )
        )
    }

    private func ingest(_ fix: CLLocation) {
        lastLocation = fix
        guard var session = navigation, let trip, let route = trip.routes.first(where: { $0.id == session.routeId }) else { return }
        let heading = travelHeading(for: fix)
        let snapshot = RouteGuidance.evaluate(
            latitude: fix.coordinate.latitude,
            longitude: fix.coordinate.longitude,
            coordinates: route.coordinates,
            maneuvers: route.maneuvers ?? [],
            durationSeconds: route.durationSeconds
        )
        session.snapshot = snapshot
        session.heading = heading
        session.userLatitude = fix.coordinate.latitude
        session.userLongitude = fix.coordinate.longitude
        session.locationProblem = nil
        navigation = session
        if session.followsUser {
            follow(fix, heading: heading)
        }
        speaker.update(snapshot: snapshot, maneuvers: route.maneuvers ?? [], destination: trip.destination.label)
        guard !snapshot.arrived else {
            offRouteSince = nil
            return
        }
        if snapshot.offRoute {
            if offRouteSince == nil { offRouteSince = Date() }
            if let offRouteSince, Date().timeIntervalSince(offRouteSince) >= 8 {
                beginReroute(from: fix)
            }
        } else {
            offRouteSince = nil
        }
    }

    private func beginReroute(from fix: CLLocation) {
        guard navigation?.rerouting != true, let destination else { return }
        if let lastRerouteAt, Date().timeIntervalSince(lastRerouteAt) < 20 { return }
        lastRerouteAt = Date()
        offRouteSince = nil
        navigation?.rerouting = true
        let here = Place(label: "Current location", lat: fix.coordinate.latitude, lng: fix.coordinate.longitude)
        rerouteTask?.cancel()
        rerouteTask = Task { await reroute(from: here, to: destination) }
    }

    private func reroute(from origin: Place, to destination: Place) async {
        do {
            let trip = try await api.routes(origin: origin, destination: destination, departAt: Date())
            guard navigation != nil else { return }
            show(trip, requestExplanation: false, adjustCamera: false)
            navigation?.routeId = trip.recommendedId
            navigation?.rerouting = false
            speaker.reset()
        } catch {
            navigation?.rerouting = false
        }
    }

    private func travelHeading(for fix: CLLocation) -> CLLocationDirection {
        if fix.speed >= 1, fix.course >= 0 {
            return fix.course
        }
        if compassHeading >= 0 {
            return compassHeading
        }
        return navigation?.heading ?? 0
    }

    private func follow(_ fix: CLLocation, heading: CLLocationDirection) {
        guard navigation?.followsUser != false else { return }
        let ahead = RouteGuidance.offset(
            latitude: fix.coordinate.latitude,
            longitude: fix.coordinate.longitude,
            bearingDegrees: heading,
            meters: 140
        )
        let aimed = MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: ahead.latitude, longitude: ahead.longitude),
            distance: 650,
            heading: heading,
            pitch: 55
        )
        followCamera = aimed
        lastAppliedHeading = heading
        mapHeading = heading
        camera = .camera(aimed)
    }

    private func headingDelta(_ lhs: CLLocationDirection, _ rhs: CLLocationDirection) -> CLLocationDirection {
        let delta = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
        return min(delta, 360 - delta)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let fix = locations.last else { return }
        Task { @MainActor in
            switch locationMode {
            case .origin:
                origin = Place(label: "Current location", lat: fix.coordinate.latitude, lng: fix.coordinate.longitude)
                here = origin
                locationMode = .idle
            case .sample:
                here = Place(label: "Current location", lat: fix.coordinate.latitude, lng: fix.coordinate.longitude)
                locationMode = .idle
            case .guidance:
                ingest(fix)
            case .idle:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in
            compassHeading = heading
            guard locationMode == .guidance, var session = navigation, let lastLocation = lastLocation, lastLocation.speed < 1 else { return }
            session.heading = heading
            navigation = session
            guard session.followsUser, headingDelta(heading, lastAppliedHeading) >= 12 else { return }
            follow(lastLocation, heading: heading)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard locationMode == .guidance else { return }
            if status == .denied || status == .restricted {
                navigation?.locationProblem = "Location access is off. Allow location to guide this drive."
            } else if status == .authorizedWhenInUse || status == .authorizedAlways {
                navigation?.locationProblem = nil
                location.startUpdatingLocation()
                location.startUpdatingHeading()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

private enum LocationMode {
    case idle
    case origin
    case sample
    case guidance
}

enum LiveActivityController {
    @MainActor
    static func start(_ trip: Trip) {
        guard let state = TripActivityContent.state(for: trip) else { return }
        let attributes = TripActivityAttributes(origin: trip.origin.label, destination: trip.destination.label)
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(60 * 60 * 3))
        for activity in Activity<TripActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        _ = try? Activity.request(attributes: attributes, content: content, pushType: nil)
    }
}
