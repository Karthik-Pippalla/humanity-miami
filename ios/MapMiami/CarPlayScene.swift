import CarPlay
import MapKit
import UIKit

final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController,
        to window: CPWindow
    ) {
        CarPlayCoordinator.shared.connect(interfaceController: interfaceController, window: window)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController,
        from window: CPWindow
    ) {
        CarPlayCoordinator.shared.disconnect()
    }
}

@MainActor
final class CarPlayCoordinator: NSObject, CPMapTemplateDelegate, MKMapViewDelegate {
    static let shared = CarPlayCoordinator()

    private var interfaceController: CPInterfaceController?
    private var mapTemplate = CPMapTemplate()
    private var mapView: MKMapView?
    private var trip: Trip?
    private var selectedId: String?
    func connect(interfaceController: CPInterfaceController, window: CPWindow) {
        self.interfaceController = interfaceController
        let map = MKMapView(frame: window.bounds)
        map.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        map.delegate = self
        map.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 25.78, longitude: -80.2),
            span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.45)
        )
        let controller = UIViewController()
        controller.view = map
        window.rootViewController = controller
        mapView = map
        mapTemplate.mapDelegate = self
        interfaceController.setRootTemplate(mapTemplate, animated: true, completion: nil)
        if let trip {
            present(trip, selectedId: selectedId ?? trip.recommendedId)
        }
    }

    func disconnect() {
        interfaceController = nil
        mapView = nil
    }

    func refresh(with trip: Trip, selectedId: String) {
        self.trip = trip
        self.selectedId = selectedId
        present(trip, selectedId: selectedId)
    }

    private func present(_ trip: Trip, selectedId: String) {
        draw(trip, selectedId: selectedId)
        guard interfaceController != nil else { return }
        let choices = trip.routes.map { route -> CPRouteChoice in
            let choice = CPRouteChoice(
                summaryVariants: [route.label, RouteFormat.minutes(route.durationSeconds)],
                additionalInformationVariants: [route.flood.summary, "Not a closure"],
                selectionSummaryVariants: ["Not a closure", route.flood.summary]
            )
            choice.userInfo = route.id as NSString
            return choice
        }
        let origin = mapItem(trip.origin)
        let destination = mapItem(trip.destination)
        let preview = CPTrip(origin: origin, destination: destination, routeChoices: choices)
        let text = CPTripPreviewTextConfiguration(
            startButtonTitle: "Details",
            additionalRoutesButtonTitle: "Routes",
            overviewButtonTitle: "Overview"
        )
        mapTemplate.showTripPreviews([preview], selectedTrip: preview, textConfiguration: text)
        CarPlayMapPanel.presentIfAvailable(on: mapTemplate, trip: trip)
    }

    private func draw(_ trip: Trip, selectedId: String) {
        guard let mapView else { return }
        mapView.removeOverlays(mapView.overlays)
        for zone in trip.floodZones {
            let polygon = MKPolygon(coordinates: zone.coordinates.map(Coordinate.make), count: zone.coordinates.count)
            polygon.title = "flood"
            mapView.addOverlay(polygon)
        }
        for zone in trip.eventZones where zone.intersectsRoute || zone.inDepartureWindow {
            let polygon = MKPolygon(coordinates: zone.coordinates.map(Coordinate.make), count: zone.coordinates.count)
            polygon.title = "event"
            mapView.addOverlay(polygon)
        }
        for route in trip.routes {
            var coords = route.coordinates.map(Coordinate.make)
            let line = MKPolyline(coordinates: &coords, count: coords.count)
            line.title = route.id
            mapView.addOverlay(line)
        }
        if let route = trip.routes.first(where: { $0.id == selectedId }) ?? trip.recommended {
            let coords = route.coordinates.map(Coordinate.make)
            mapView.setVisibleMapRect(MKPolygon(coordinates: coords, count: coords.count).boundingMapRect, edgePadding: UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40), animated: true)
        }
    }

    private func mapItem(_ place: Place) -> MKMapItem {
        let item = MKMapItem(location: CLLocation(latitude: place.lat, longitude: place.lng), address: nil)
        item.name = place.label
        return item
    }

    func mapTemplate(_ mapTemplate: CPMapTemplate, selectedPreviewFor trip: CPTrip, using routeChoice: CPRouteChoice) {
        guard let id = routeChoice.userInfo as? String, let current = self.trip else { return }
        selectedId = id
        draw(current, selectedId: id)
        TripStore.shared.select(id, updateCarPlay: false)
    }

    func mapTemplate(_ mapTemplate: CPMapTemplate, startedTrip trip: CPTrip, using routeChoice: CPRouteChoice) {
        let action = CPAlertAction(title: "OK", style: .default, handler: { _ in })
        let alert = CPNavigationAlert(
            titleVariants: ["Route preview"],
            subtitleVariants: ["Survive Miami does not give turn-by-turn guidance. The line is estimated exposure, not a closure."],
            image: nil,
            primaryAction: action,
            secondaryAction: nil,
            duration: 8
        )
        mapTemplate.present(navigationAlert: alert, animated: true)
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let polygon = overlay as? MKPolygon {
            let renderer = MKPolygonRenderer(polygon: polygon)
            let event = overlay.title == "event"
            let amber = UIColor(red: 226.0 / 255, green: 176.0 / 255, blue: 67.0 / 255, alpha: 1)
            renderer.fillColor = (event ? amber : UIColor.systemBlue).withAlphaComponent(0.28)
            renderer.strokeColor = event ? amber : .systemBlue
            renderer.lineWidth = 1
            return renderer
        }
        let renderer = MKPolylineRenderer(overlay: overlay)
        let selected = overlay.title == selectedId
        renderer.strokeColor = selected ? UIColor(red: 240.0 / 255, green: 120.0 / 255, blue: 80.0 / 255, alpha: 1) : .systemGray
        renderer.lineWidth = selected ? 7 : 4
        return renderer
    }
}
