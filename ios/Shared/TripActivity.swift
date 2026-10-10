import ActivityKit
import Foundation

struct TripActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        var minutes: Int
        var floodOverlapMeters: Double
        var summary: String
    }

    var origin: String
    var destination: String
}

enum TripActivityContent {
    static func state(for trip: Trip) -> TripActivityAttributes.ContentState? {
        guard let route = trip.recommended else { return nil }
        return TripActivityAttributes.ContentState(
            minutes: max(1, Int((route.durationSeconds / 60).rounded())),
            floodOverlapMeters: route.flood.overlapMeters,
            summary: route.flood.summary
        )
    }
}
