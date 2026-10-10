import Foundation
import Testing

struct MapMiamiLogicTests {
    @Test func decodesATripFromTheAPI() throws {
        let trip = try APICoding.decoder.decode(Trip.self, from: Data(SampleTrip.json.utf8))
        #expect(trip.recommendedId == "detour")
        #expect(trip.routes.count == 2)
        #expect(trip.routes[0].coordinates.first?.latitude == 25.76)
        #expect(trip.floodZones.first?.coordinates.first?.longitude == -80.185)
        #expect(trip.notice.contains("not a reported road closure"))
        #expect(trip.routes[0].maneuvers == nil)
    }

    @Test func decodesTurnInstructionsWhenPresent() throws {
        let trip = try APICoding.decoder.decode(Trip.self, from: Data(SampleTrip.withManeuver.utf8))
        let step = try #require(trip.routes[0].maneuvers?.first)
        #expect(step.type == 10)
        #expect(step.instruction == "Turn right onto Brickell Avenue.")
        #expect(step.lengthMeters == 400)
        #expect(step.beginShapeIndex == 2)
    }

    @Test func guidanceSnapsToTheLineAndNamesTheNextTurn() {
        let north = 1_000.0 / 110_540.0
        let coordinates = [
            (latitude: 25.0, longitude: -80.0),
            (latitude: 25.0 + north, longitude: -80.0),
            (latitude: 25.0 + north * 2, longitude: -80.0),
        ]
        let maneuvers = [
            RouteManeuver(type: 8, instruction: "Head north", lengthMeters: 1000, timeSeconds: 60, beginShapeIndex: 0, endShapeIndex: 1),
            RouteManeuver(type: 10, instruction: "Turn right", lengthMeters: 1000, timeSeconds: 70, beginShapeIndex: 1, endShapeIndex: 2),
        ]
        let east = 10 / (111_320.0 * cos(25 * .pi / 180))
        let snapshot = RouteGuidance.evaluate(
            latitude: 25.0 + north / 2,
            longitude: -80.0 + east,
            coordinates: coordinates,
            maneuvers: maneuvers,
            durationSeconds: 130
        )
        #expect(snapshot.distanceFromLineMeters > 5 && snapshot.distanceFromLineMeters < 20)
        #expect(snapshot.distanceAlongMeters > 450 && snapshot.distanceAlongMeters < 550)
        #expect(snapshot.upcomingManeuverIndex == 1)
        #expect(snapshot.distanceToManeuverMeters > 450 && snapshot.distanceToManeuverMeters < 550)
        #expect(snapshot.timeRemainingSeconds > 90 && snapshot.timeRemainingSeconds < 110)
        #expect(!snapshot.arrived)
        #expect(!snapshot.offRoute)
    }

    @Test func traveledPortionSplitsAtTheDrivenDistance() {
        let north = 2_000.0 / 110_540.0
        let coordinates = [
            (latitude: 25.0, longitude: -80.0),
            (latitude: 25.0 + north, longitude: -80.0),
        ]
        let parts = RouteGuidance.split(coordinates: coordinates, distanceAlongMeters: 1_000)
        #expect(parts.traveled.count >= 2)
        #expect(parts.remaining.count >= 2)
        let cut = parts.traveled[parts.traveled.count - 1]
        #expect(abs(cut.latitude - (25.0 + north / 2)) < 0.0002)
        #expect(abs(cut.longitude + 80) < 0.0002)
        #expect(abs(parts.remaining[0].latitude - cut.latitude) < 0.00001)
    }

    @Test func guidanceMarksArrivalAndOffRoute() {
        let north = 1_000.0 / 110_540.0
        let coordinates = [
            (latitude: 25.0, longitude: -80.0),
            (latitude: 25.0 + north * 2, longitude: -80.0),
        ]
        let arrived = RouteGuidance.evaluate(
            latitude: 25.0 + north * 2,
            longitude: -80.0,
            coordinates: coordinates,
            maneuvers: [],
            durationSeconds: 120
        )
        #expect(arrived.arrived)
        #expect(!arrived.offRoute)

        let east = 200 / (111_320.0 * cos(25 * .pi / 180))
        let away = RouteGuidance.evaluate(
            latitude: 25.0,
            longitude: -80.0 + east,
            coordinates: coordinates,
            maneuvers: [],
            durationSeconds: 120
        )
        #expect(!away.arrived)
        #expect(away.offRoute)
        #expect(away.distanceFromLineMeters > 45)
    }

    @Test func scoreNoteMatchesTheRouteScores() throws {
        let trip = try APICoding.decoder.decode(Trip.self, from: Data(SampleTrip.json.utf8))
        let note = ScoreNote.text(for: trip)
        #expect(note.contains("Avoidance detour is recommended"))
        #expect(note.contains("does not cross a mapped special flood hazard area"))
        #expect(note.contains("Fastest drive is about 13.3 minutes"))
    }

    @Test func explainFailureMessageIsReadable() {
        let data = Data(#"{"detail":"Survive Miami currently routes in South Florida."}"#.utf8)
        #expect(APIClient.message(from: data, status: 400) == "Survive Miami currently routes in South Florida.")
    }

    @Test func miamiTimestampDropsTheZone() {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(identifier: "America/New_York")
        components.year = 2026
        components.month = 10
        components.day = 10
        components.hour = 18
        components.minute = 30
        let date = components.date!
        #expect(APIClient.miamiNaiveTimestamp(date) == "2026-10-10T18:30:00")
    }

    @Test func compareActionRequiresBothPlaces() async {
        await clearStores()
        do {
            _ = try await CompareRouteAction.perform(origin: " ", destination: "Miami Beach", departAt: nil, planner: FakePlanner())
            Issue.record("Blank origin should fail")
        } catch CompareRouteError.missingPlace {
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    @Test func compareActionSavesTheTripForSiriHandoff() async throws {
        await clearStores()
        let trip = try await CompareRouteAction.perform(
            origin: "Calle Ocho",
            destination: "Miami Beach",
            departAt: nil,
            planner: FakePlanner()
        )
        #expect(trip.origin.label == "Calle Ocho")
        #expect(CompareRouteAction.dialog(origin: "Calle Ocho", destination: "Miami Beach").contains("flood-aware"))
        #expect(RecentTripStore.all().first?.id == "Calle Ocho→Miami Beach")
        #expect(TripHandoff.load()?.destination.label == "Miami Beach")
    }

    @Test func onScreenAnnotationIsWhatSiriDescribes() async throws {
        await MainActor.run {
            OnScreenRoutes.focus(
                AnnotatedRoute(
                    id: "fastest",
                    label: "Fastest drive",
                    summary: "No active flood alert, so flood areas are not shown.",
                    minutes: "13 min",
                    recommended: true
                )
            )
        }
        let sentence = try await MainActor.run { try DescribeRouteAction.sentence() }
        #expect(sentence.contains("Fastest drive"))
        #expect(sentence.contains("not a road closure"))
        await MainActor.run { OnScreenRoutes.clear("fastest") }
        await MainActor.run {
            #expect(throws: CompareRouteError.noRouteOnScreen) {
                try DescribeRouteAction.sentence()
            }
        }
    }

    private func clearStores() async {
        UserDefaults.standard.removeObject(forKey: "mapmiami.recentTrips")
        UserDefaults.standard.removeObject(forKey: "mapmiami.latestTrip")
    }
}

private struct FakePlanner: TripPlanning {
    func plan(originQuery: String, destinationQuery: String, departAt: Date?) async throws -> Trip {
        var trip = try APICoding.decoder.decode(Trip.self, from: Data(SampleTrip.json.utf8))
        trip.origin.label = originQuery
        trip.destination.label = destinationQuery
        return trip
    }
}

private enum SampleTrip {
    static let json = """
    {
      "origin": {"label": "Calle Ocho", "lat": 25.7653, "lng": -80.2196},
      "destination": {"label": "Miami Beach Convention Center", "lat": 25.7907, "lng": -80.13},
      "recommended_id": "detour",
      "routes": [
        {
          "id": "fastest",
          "label": "Fastest drive",
          "geometry": {"type": "LineString", "coordinates": [[-80.22, 25.76], [-80.13, 25.79]]},
          "duration_seconds": 800,
          "distance_meters": 10000,
          "has_toll": true,
          "flood": {
            "estimated_risk": true,
            "closure": false,
            "intersecting": true,
            "zone_ids": ["md-1"],
            "overlap_meters": 120,
            "summary": "An active flood alert is in effect. Estimated exposure: the drive crosses mapped flood zone AE. This is not a reported road closure."
          },
          "events": [],
          "score": {
            "duration_seconds": 800,
            "flood_zone_count": 1,
            "flood_overlap_meters": 120,
            "events_in_window": 0,
            "flood_penalty_seconds": 198,
            "event_penalty_seconds": 0,
            "total_seconds": 998,
            "weights": {"note": "Penalties estimate mapped exposure."}
          }
        },
        {
          "id": "detour",
          "label": "Avoidance detour",
          "geometry": {"type": "LineString", "coordinates": [[-80.22, 25.82], [-80.13, 25.83]]},
          "duration_seconds": 900,
          "distance_meters": 12000,
          "has_toll": false,
          "flood": {
            "estimated_risk": true,
            "closure": false,
            "intersecting": false,
            "zone_ids": [],
            "overlap_meters": 0,
            "summary": "An active flood alert is in effect. This drive does not cross a mapped special flood hazard area."
          },
          "events": [],
          "score": {
            "duration_seconds": 900,
            "flood_zone_count": 0,
            "flood_overlap_meters": 0,
            "events_in_window": 0,
            "flood_penalty_seconds": 0,
            "event_penalty_seconds": 0,
            "total_seconds": 900,
            "weights": {"note": "Penalties estimate mapped exposure."}
          }
        }
      ],
      "flood_zones": [
        {"id": "md-1", "zone": "AE", "subtype": null, "ring": [[-80.185, 25.755], [-80.155, 25.755], [-80.155, 25.785], [-80.185, 25.785]]}
      ],
      "event_zones": [],
      "weather": {"forecast": "Heavy rain", "temperature_f": 81, "alerts": ["Flood Warning for Miami-Dade"], "flood_active": true},
      "explanation": null,
      "explanation_facts": {"recommended_id": "detour", "closure": false},
      "data_gaps": [],
      "sources": {"routing": "Valhalla"},
      "notice": "They are estimated exposure, not a reported road closure."
    }
    """

    static let withManeuver = json.replacingOccurrences(
        of: "\"id\": \"fastest\"",
        with: "\"id\": \"fastest\", \"maneuvers\": [{\"type\": 10, \"instruction\": \"Turn right onto Brickell Avenue.\", \"length_meters\": 400, \"time_seconds\": 30, \"begin_shape_index\": 2, \"end_shape_index\": 8}]"
    )
}
