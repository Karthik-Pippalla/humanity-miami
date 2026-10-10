import Foundation

protocol TripPlanning: Sendable {
    func plan(originQuery: String, destinationQuery: String, departAt: Date?) async throws -> Trip
}

enum CompareRouteError: Error, Equatable {
    case missingPlace
    case noRouteOnScreen
}

enum CompareRouteAction {
    static func dialog(origin: String, destination: String) -> String {
        "Comparing a flood-aware route from \(origin) to \(destination)."
    }

    static func perform(
        origin: String,
        destination: String,
        departAt: Date?,
        planner: any TripPlanning
    ) async throws -> Trip {
        let from = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard from.count >= 2, to.count >= 2 else { throw CompareRouteError.missingPlace }
        let trip = try await planner.plan(originQuery: from, destinationQuery: to, departAt: departAt)
        RecentTripStore.save(origin: trip.origin.label, destination: trip.destination.label)
        TripHandoff.save(trip)
        return trip
    }
}

struct AnnotatedRoute: Equatable, Sendable {
    var id: String
    var label: String
    var summary: String
    var minutes: String
    var recommended: Bool
}

@MainActor
enum OnScreenRoutes {
    static var focused: AnnotatedRoute?

    static func focus(_ route: AnnotatedRoute) {
        focused = route
    }

    static func clear(_ id: String) {
        if focused?.id == id {
            focused = nil
        }
    }
}

enum DescribeRouteAction {
    @MainActor
    static func sentence() throws -> String {
        guard let route = OnScreenRoutes.focused else { throw CompareRouteError.noRouteOnScreen }
        let role = route.recommended ? "Recommended" : "Alternate"
        return "\(role): \(route.label), about \(route.minutes). \(route.summary) This is not a road closure."
    }
}

enum RecentTripStore {
    private static let key = "mapmiami.recentTrips"

    static func save(origin: String, destination: String) {
        var records = all().filter { !($0.origin == origin && $0.destination == destination) }
        records.insert(RecentTripRecord(origin: origin, destination: destination), at: 0)
        if let data = try? JSONEncoder().encode(Array(records.prefix(8))) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func all() -> [RecentTripRecord] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let records = try? JSONDecoder().decode([RecentTripRecord].self, from: data) else {
            return []
        }
        return records
    }
}

struct RecentTripRecord: Codable, Equatable, Sendable, Identifiable {
    var origin: String
    var destination: String

    var id: String { "\(origin)→\(destination)" }
}

enum TripHandoff {
    private static let key = "mapmiami.latestTrip"

    static func save(_ trip: Trip) {
        if let data = try? APICoding.encoder.encode(trip) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func load() -> Trip? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? APICoding.decoder.decode(Trip.self, from: data)
    }
}
