import MapKit
import SwiftUI

struct MapScreen: View {
    @Bindable var store: TripStore

    var body: some View {
        MapReader { proxy in
            Map(position: Binding(get: { store.camera }, set: { store.adoptMapPosition($0) })) {
                if store.navigation == nil {
                    UserAnnotation()
                } else if let latitude = store.navigation?.userLatitude, let longitude = store.navigation?.userLongitude {
                    Annotation("", coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)) {
                        NavigationArrow(degrees: (store.navigation?.heading ?? 0) - store.mapHeading)
                    }
                    .annotationTitles(.hidden)
                }
                if store.featureMode == .plan, let plan = store.dayPlan {
                    MapPolyline(coordinates: plan.geometry.coordinates.compactMap { pair in
                        guard pair.count >= 2 else { return nil }
                        return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
                    })
                    .stroke(Color.accentColor, lineWidth: 6)
                    ForEach(Array(plan.stops.enumerated()), id: \.element.id) { index, stop in
                        Marker("\(index + 1). \(stop.name)", coordinate: CLLocationCoordinate2D(latitude: stop.lat, longitude: stop.lng))
                    }
                } else if let trip = store.trip {
                    ForEach(trip.floodZones) { zone in
                        MapPolygon(coordinates: zone.coordinates.map(Coordinate.make))
                            .foregroundStyle(Color.blue.opacity(0.28))
                            .stroke(Color.blue, lineWidth: 1)
                    }
                    ForEach(trip.eventZones.filter { $0.intersectsRoute || $0.inDepartureWindow }) { zone in
                        MapPolygon(coordinates: zone.coordinates.map(Coordinate.make))
                            .foregroundStyle(BrandColor.amber.opacity(0.35))
                            .stroke(BrandColor.amber, lineWidth: 1)
                    }
                    ForEach(visibleRoutes(in: trip)) { route in
                        RouteLines(route: route, navigation: store.navigation, selected: route.id == store.selectedId)
                    }
                    if store.navigation == nil {
                        ForEach(Array(trip.routes.enumerated()), id: \.element.id) { index, route in
                            if let point = RouteGuidance.labelCoordinate(
                                coordinates: route.coordinates,
                                slot: index,
                                count: trip.routes.count
                            ) {
                                Annotation("", coordinate: Coordinate.make(point), anchor: .bottom) {
                                    RouteStartPill(
                                        minutes: RouteFormat.minutes(route.durationSeconds),
                                        selected: route.id == store.selectedId,
                                        onSelect: { store.select(route.id) },
                                        onStart: { store.startNavigation(routeId: route.id) }
                                    )
                                }
                                .annotationTitles(.hidden)
                            }
                        }
                    }
                    Marker(trip.origin.label, coordinate: CLLocationCoordinate2D(latitude: trip.origin.lat, longitude: trip.origin.lng))
                    Marker(trip.destination.label, coordinate: CLLocationCoordinate2D(latitude: trip.destination.lat, longitude: trip.destination.lng))
                }
            }
            .simultaneousGesture(
                SpatialTapGesture().onEnded { event in
                    Keyboard.hide()
                    guard store.navigation == nil, let coordinate = proxy.convert(event.location, from: .local) else { return }
                    store.selectRoute(near: coordinate)
                }
            )
            .simultaneousGesture(DragGesture(minimumDistance: 12).onChanged { _ in store.pauseFollow() })
            .simultaneousGesture(MagnifyGesture().onChanged { _ in store.pauseFollow() })
            .simultaneousGesture(RotateGesture().onChanged { _ in store.pauseFollow() })
            .onMapCameraChange { context in
                store.noteMapHeading(context.camera.heading)
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls {
            if store.navigation == nil {
                MapUserLocationButton()
                MapCompass()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let navigation = store.navigation, let trip = store.trip {
                ManeuverBanner(
                    navigation: navigation,
                    route: trip.routes.first { $0.id == navigation.routeId },
                    destination: trip.destination.label
                )
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let navigation = store.navigation, let trip = store.trip {
                NavigationStatusBar(
                    snapshot: navigation.snapshot,
                    fallbackSeconds: trip.routes.first { $0.id == navigation.routeId }?.durationSeconds ?? 0,
                    onEnd: { store.endNavigation() }
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            } else {
                TripSheet(store: store)
                    .background(BrandColor.navy, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .preferredColorScheme(.dark)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if store.navigation?.followsUser == false {
                Button {
                    store.resumeFollow()
                } label: {
                    Label("Re-center", systemImage: "location.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BrandColor.navy)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.white, in: Capsule())
                        .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 16)
                .padding(.bottom, 108)
                .accessibilityHint("Tilts the map back to the direction of travel")
            }
        }
        .overlay {
            if store.loading {
                ZStack {
                    BrandColor.navy.opacity(0.96).ignoresSafeArea()
                    VStack(spacing: 18) {
                        SurviveLogo(drawing: true, showsWordmark: true, stacked: true)
                        Text("Checking routes…")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(24)
                }
                .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    private func visibleRoutes(in trip: Trip) -> [RouteCandidate] {
        guard let routeId = store.navigation?.routeId else { return trip.routes }
        return trip.routes.filter { $0.id == routeId }
    }
}

private struct RouteLines: MapContent {
    var route: RouteCandidate
    var navigation: ActiveNavigation?
    var selected: Bool

    var body: some MapContent {
        if let navigation, navigation.routeId == route.id, let along = navigation.snapshot?.distanceAlongMeters {
            let parts = RouteGuidance.split(coordinates: route.coordinates, distanceAlongMeters: along)
            if parts.traveled.count >= 2 {
                MapPolyline(coordinates: parts.traveled.map(Coordinate.make))
                    .stroke(Color.gray, lineWidth: 6)
            }
            if parts.remaining.count >= 2 {
                MapPolyline(coordinates: parts.remaining.map(Coordinate.make))
                    .stroke(Color.accentColor, lineWidth: 7)
            }
        } else {
            MapPolyline(coordinates: route.coordinates.map(Coordinate.make))
                .stroke(selected || navigation?.routeId == route.id ? Color.accentColor : Color.secondary, lineWidth: selected || navigation?.routeId == route.id ? 7 : 4)
        }
    }
}

private struct NavigationArrow: View {
    var degrees: Double

    var body: some View {
        Image(systemName: "location.north.fill")
            .font(.title2)
            .foregroundStyle(.white)
            .padding(7)
            .background(Color.accentColor, in: Circle())
            .overlay {
                Circle().stroke(.white, lineWidth: 2)
            }
            .rotationEffect(.degrees(degrees))
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            .accessibilityLabel("Your location")
    }
}

private struct RouteStartPill: View {
    var minutes: String
    var selected: Bool
    var onSelect: () -> Void
    var onStart: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onSelect) {
                Text(minutes)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BrandColor.navy)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(minutes) route")
            .accessibilityHint("Selects this route")
            Button(action: onStart) {
                Text("Start")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(BrandColor.coral, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Starts guidance along this route")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(selected ? Color.white : Color.white.opacity(0.92), in: Capsule())
        .overlay {
            Capsule().strokeBorder(selected ? BrandColor.coral : Color.clear, lineWidth: 2)
        }
        .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
    }
}

enum Coordinate {
    static func make(_ pair: (latitude: Double, longitude: Double)) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: pair.latitude, longitude: pair.longitude)
    }
}
