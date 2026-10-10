import Foundation

struct Place: Codable, Equatable, Hashable, Sendable {
    var label: String
    var lat: Double
    var lng: Double
}

struct ScoreBreakdown: Codable, Equatable, Sendable {
    var durationSeconds: Double
    var floodZoneCount: Int
    var floodOverlapMeters: Double
    var eventsInWindow: Int
    var floodPenaltySeconds: Double
    var eventPenaltySeconds: Double
    var totalSeconds: Double
    var weights: JSONValue
}

struct FloodExposure: Codable, Equatable, Sendable {
    var estimatedRisk: Bool
    var closure: Bool
    var intersecting: Bool
    var zoneIds: [String]
    var overlapMeters: Double
    var summary: String
}

struct EventHit: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var venue: String
    var start: String?
    var end: String?
    var intersectsRoute: Bool
    var inDepartureWindow: Bool
}

struct GeoLine: Codable, Equatable, Sendable {
    var type: String
    var coordinates: [[Double]]
}

struct RouteManeuver: Codable, Equatable, Sendable {
    var type: Int
    var instruction: String
    var lengthMeters: Double
    var timeSeconds: Double
    var beginShapeIndex: Int
    var endShapeIndex: Int
}

struct RouteCandidate: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var label: String
    var geometry: GeoLine
    var durationSeconds: Double
    var distanceMeters: Double
    var hasToll: Bool
    var flood: FloodExposure
    var events: [EventHit]
    var score: ScoreBreakdown
    /// Absent on trips saved before turn instructions were returned.
    var maneuvers: [RouteManeuver]?
}

struct FloodZonePolygon: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var zone: String
    var subtype: String?
    var ring: [[Double]]
}

struct EventZonePolygon: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var venue: String
    var start: String?
    var end: String?
    var ring: [[Double]]
    var intersectsRoute: Bool
    var inDepartureWindow: Bool
}

struct WeatherSnapshot: Codable, Equatable, Sendable {
    var forecast: String?
    var temperatureF: Double?
    var alerts: [String]
    var floodActive: Bool
}

struct Explanation: Codable, Equatable, Sendable {
    var text: String
    var model: String
    var basedOn: String?
}

struct Trip: Codable, Equatable, Sendable {
    var origin: Place
    var destination: Place
    var recommendedId: String
    var routes: [RouteCandidate]
    var floodZones: [FloodZonePolygon]
    var eventZones: [EventZonePolygon]
    var weather: WeatherSnapshot?
    var explanation: Explanation?
    var explanationFacts: JSONValue
    var dataGaps: [String]
    var sources: JSONValue?
    var notice: String

    var recommended: RouteCandidate? {
        routes.first { $0.id == recommendedId } ?? routes.first
    }
}

struct WeatherAdvisory: Codable, Equatable, Sendable, Identifiable {
    var event: String
    var headline: String
    var severity: String?
    var urgency: String?
    var instruction: String?
    var onset: String?
    var ends: String?
    var category: String
    var isWatch: Bool
    var plainLanguage: String?

    var id: String { "\(event)-\(headline)" }
}

struct CityAlerts: Codable, Equatable, Sendable {
    var place: String
    var forecast: String?
    var temperatureF: Double?
    var alerts: [String]
    var floodActive: Bool
    var notice: String
    var advisories: [WeatherAdvisory]?
    var language: String?
    var dataGaps: [String]?
    var lat: Double?
    var lng: Double?
}

struct ChecklistItem: Codable, Equatable, Sendable, Identifiable {
    var category: String
    var action: String
    var why: String

    var id: String { "\(category)-\(action)" }
}

struct PrepareResult: Codable, Equatable, Sendable {
    var items: [ChecklistItem]
    var model: String
    var language: String
    var alerts: [String]
    var dataGaps: [String]
    var notice: String
}

struct ResourceCard: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var kind: String
    var address: String
    var lat: Double
    var lng: Double
    var serves: [String]
    var sourceUrl: String
    var driveMinutes: Double?
    var distanceMeters: Double?
    var estimated: Bool
    var confirm: String
}

struct AssistResult: Codable, Equatable, Sendable {
    var resources: [ResourceCard]
    var steps: [ChecklistItem]
    var model: String
    var language: String
    var alerts: [String]
    var dataGaps: [String]
    var notice: String
}

struct ItineraryStop: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var lat: Double
    var lng: Double
    var arrival: String
    var dwellMinutes: Int
    var leave: String
    var travelMinutes: Double?
    var why: String
}

struct DayPlan: Codable, Equatable, Sendable {
    var stops: [ItineraryStop]
    var geometry: GeoLine
    var note: String
    var model: String
    var timingSource: String
    var language: String
    var dataGaps: [String]
    var notice: String
}

struct ExplainResult: Codable, Equatable, Sendable {
    var explanation: Explanation
    var dataGaps: [String]
}

enum TripNotice {
    static let beforeRequest = "Travel time is a typical drive, not live traffic. Blue flood areas appear only when a flood warning or advisory is active. They are estimated exposure, not a reported road closure."
}

enum GapCopy {
    static func text(for gap: String) -> String {
        switch gap {
        case "ticketmaster_unconfigured":
            return "Event listings need a Ticketmaster API key."
        case "gemini_unavailable":
            return "Gemma 4 did not respond, so this uses the built-in note."
        case "flood_zones_unavailable":
            return "Flood-zone polygons could not be loaded, so exposure was not scored."
        case "flood_zones_truncated":
            return "Only part of the flood-zone layer was returned for this area."
        case "weather_unavailable":
            return "National Weather Service data could not be loaded."
        case "valhalla_avoid_failed":
            return "A route that avoids the exposed stretches could not be calculated."
        case "events_unavailable":
            return "Event listings could not be loaded."
        case "live_traffic_unavailable":
            return "Live traffic was unavailable, so times are a typical drive for that time of day."
        case "routing_unavailable":
            return "A drive time could not be calculated for every stop."
        case "planner_adjusted":
            return "A place that was not in the Miami catalog was left out of the plan."
        default:
            return gap
        }
    }
}

enum DemoTrip {
    static let origin = Place(label: "Calle Ocho, Little Havana", lat: 25.7653, lng: -80.2196)
    static let destination = Place(label: "Miami Beach Convention Center", lat: 25.7907, lng: -80.13)
}

enum RouteFormat {
    static func minutes(_ seconds: Double) -> String {
        let total = max(1, Int((seconds / 60).rounded()))
        if total < 60 { return "\(total) min" }
        let hours = total / 60
        let rest = total % 60
        return rest == 0 ? "\(hours) hr" : "\(hours) hr \(rest) min"
    }

    static func miles(_ meters: Double) -> String {
        String(format: "%.1f mi", meters / 1609.344)
    }

    static func oneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

extension RouteCandidate {
    /// GeoJSON positions are longitude, latitude.
    var coordinates: [(latitude: Double, longitude: Double)] {
        geometry.coordinates.compactMap { pair in
            guard pair.count >= 2 else { return nil }
            return (latitude: pair[1], longitude: pair[0])
        }
    }
}

extension FloodZonePolygon {
    var coordinates: [(latitude: Double, longitude: Double)] {
        ring.compactMap { pair in
            guard pair.count >= 2 else { return nil }
            return (latitude: pair[1], longitude: pair[0])
        }
    }
}

extension EventZonePolygon {
    var coordinates: [(latitude: Double, longitude: Double)] {
        ring.compactMap { pair in
            guard pair.count >= 2 else { return nil }
            return (latitude: pair[1], longitude: pair[0])
        }
    }
}

/// Opens the same drive in Apple Maps or Google Maps.
///
/// Neither app accepts a custom polyline for turn-by-turn navigation. These links
/// place pass-through points along our line so the other app rebuilds a drive
/// through those points. Google Maps treats them as via points and does not stop.
/// Apple Maps treats them as stops and still chooses the roads between stops.
enum ExternalDirections {
    struct Links: Equatable {
        var apple: URL
        var google: URL
        var viaPoints: [(latitude: Double, longitude: Double)]

        static func == (lhs: Links, rhs: Links) -> Bool {
            guard lhs.apple == rhs.apple, lhs.google == rhs.google, lhs.viaPoints.count == rhs.viaPoints.count else {
                return false
            }
            return zip(lhs.viaPoints, rhs.viaPoints).allSatisfy {
                $0.latitude == $1.latitude && $0.longitude == $1.longitude
            }
        }
    }

    static let maximumViaPoints = 8

    static func links(origin: Place, destination: Place, coordinates: [(latitude: Double, longitude: Double)]) -> Links? {
        let via = viaPoints(along: coordinates)
        guard let apple = appleURL(origin: origin, destination: destination, via: via),
              let google = googleURL(origin: origin, destination: destination, via: via) else {
            return nil
        }
        return Links(apple: apple, google: google, viaPoints: via)
    }

    static func viaPoints(along coordinates: [(latitude: Double, longitude: Double)]) -> [(latitude: Double, longitude: Double)] {
        guard coordinates.count >= 2 else { return [] }
        var cumulative = [0.0]
        cumulative.reserveCapacity(coordinates.count)
        for index in 1..<coordinates.count {
            cumulative.append(cumulative[index - 1] + meters(from: coordinates[index - 1], to: coordinates[index]))
        }
        let total = cumulative[cumulative.count - 1]
        guard total >= 800 else { return [] }
        let count = min(maximumViaPoints, max(1, Int(total / 1_200)))
        var chosen: [(latitude: Double, longitude: Double)] = []
        for slot in 1...count {
            let target = total * Double(slot) / Double(count + 1)
            guard let point = point(at: target, coordinates: coordinates, cumulative: cumulative) else { continue }
            let fromStart = target
            let fromEnd = total - target
            guard fromStart > 250, fromEnd > 250 else { continue }
            if let previous = chosen.last, meters(from: previous, to: point) < 200 { continue }
            chosen.append(point)
        }
        return chosen
    }

    private static func appleURL(origin: Place, destination: Place, via: [(latitude: Double, longitude: Double)]) -> URL? {
        let stops = via.map(format) + [format(latitude: destination.lat, longitude: destination.lng)]
        let raw = "https://maps.apple.com/?saddr=\(format(latitude: origin.lat, longitude: origin.lng))&daddr=\(stops.joined(separator: "+to:"))&dirflg=d"
        return URL(string: raw)
    }

    private static func googleURL(origin: Place, destination: Place, via: [(latitude: Double, longitude: Double)]) -> URL? {
        var items = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "origin", value: format(latitude: origin.lat, longitude: origin.lng)),
            URLQueryItem(name: "destination", value: format(latitude: destination.lat, longitude: destination.lng)),
            URLQueryItem(name: "travelmode", value: "driving"),
            URLQueryItem(name: "dir_action", value: "navigate"),
        ]
        if !via.isEmpty {
            items.append(URLQueryItem(name: "waypoints", value: via.map { "via:\(format($0))" }.joined(separator: "|")))
        }
        var components = URLComponents(string: "https://www.google.com/maps/dir/")
        components?.queryItems = items
        return components?.url
    }

    private static func point(
        at target: Double,
        coordinates: [(latitude: Double, longitude: Double)],
        cumulative: [Double]
    ) -> (latitude: Double, longitude: Double)? {
        guard let index = cumulative.lastIndex(where: { $0 <= target }), index < coordinates.count - 1 else {
            return coordinates.last
        }
        let span = cumulative[index + 1] - cumulative[index]
        let fraction = span > 0 ? (target - cumulative[index]) / span : 0
        let start = coordinates[index]
        let end = coordinates[index + 1]
        return (
            latitude: start.latitude + (end.latitude - start.latitude) * fraction,
            longitude: start.longitude + (end.longitude - start.longitude) * fraction
        )
    }

    private static func meters(
        from start: (latitude: Double, longitude: Double),
        to end: (latitude: Double, longitude: Double)
    ) -> Double {
        let earth = 6_371_000.0
        let lat1 = start.latitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let dLat = (end.latitude - start.latitude) * .pi / 180
        let dLng = (end.longitude - start.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLng / 2) * sin(dLng / 2)
        return 2 * earth * asin(min(1, sqrt(h)))
    }

    private static func format(latitude: Double, longitude: Double) -> String {
        String(format: "%.5f,%.5f", locale: Locale(identifier: "en_US_POSIX"), latitude, longitude)
    }

    private static func format(_ point: (latitude: Double, longitude: Double)) -> String {
        format(latitude: point.latitude, longitude: point.longitude)
    }
}
