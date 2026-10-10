import Foundation
import MapKit

struct LiveTripPlanner: TripPlanning {
    func plan(originQuery: String, destinationQuery: String, departAt: Date?) async throws -> Trip {
        let origin = try await PlaceLookup.firstPlace(matching: originQuery)
        let destination = try await PlaceLookup.firstPlace(matching: destinationQuery)
        return try await APIClient().routes(origin: origin, destination: destination, departAt: departAt)
    }
}

enum TripPlanner {
    static var shared: any TripPlanning = LiveTripPlanner()
}
