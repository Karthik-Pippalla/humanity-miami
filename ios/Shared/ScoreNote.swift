import Foundation

enum ScoreNote {
    /// The same kind of sentence the API writes from route scores when Gemma is unavailable.
    static func text(for trip: Trip) -> String {
        guard let recommended = trip.recommended else {
            return "No route score was available to explain."
        }
        var sentences: [String] = [
            "\(recommended.label) is recommended. It is about \(RouteFormat.oneDecimal(recommended.durationSeconds / 60)) minutes and \(RouteFormat.oneDecimal(recommended.distanceMeters / 1000)) km.",
        ]
        if trip.dataGaps.contains("flood_zones_unavailable") {
            sentences.append("Flood-zone polygons could not be loaded, so flood exposure was not scored.")
        } else if trip.weather?.floodActive == true {
            let crossed = recommended.flood.zoneIds.count
            if crossed > 0 {
                let noun = crossed == 1 ? "zone" : "zones"
                sentences.append(
                    "An active flood alert is in effect, and this drive crosses \(crossed) mapped flood \(noun). That is estimated exposure, not a road closure."
                )
            } else {
                sentences.append(
                    "An active flood alert is in effect, and this drive does not cross a mapped special flood hazard area."
                )
            }
        } else {
            sentences.append("No active flood alert is in effect, so flood areas are not part of this score.")
        }

        let affecting = recommended.events.filter(\.inDepartureWindow)
        let later = recommended.events.filter { !$0.inDepartureWindow }
        if !affecting.isEmpty {
            let names = affecting.prefix(3).map(\.name).joined(separator: ", ")
            let verb = affecting.count == 1 ? "falls" : "fall"
            sentences.append(
                "\(names) \(verb) in this departure window. That is estimated venue congestion, not measured traffic."
            )
        }
        if !later.isEmpty {
            let details = later.prefix(3).map { event in
                event.venue.isEmpty ? event.name : "\(event.name) at \(event.venue)"
            }
            let subject = details.count == 1 ? "That event" : "Those events"
            sentences.append("\(details.joined(separator: "; ")). \(subject) will not affect this ride.")
        } else if affecting.isEmpty {
            sentences.append("No listed event falls in this departure window.")
        }

        if let other = trip.routes.first(where: { $0.id != recommended.id }) {
            sentences.append(
                "\(other.label) is about \(RouteFormat.oneDecimal(other.durationSeconds / 60)) minutes. Its score is higher, so it is not the recommendation."
            )
        }
        return sentences.joined(separator: " ")
    }
}
