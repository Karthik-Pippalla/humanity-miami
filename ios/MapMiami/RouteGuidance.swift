import Foundation

enum RouteGuidance {
    static let arrivalMeters = 30.0
    static let offRouteMeters = 45.0

    struct Snapshot: Equatable {
        var distanceFromLineMeters: Double
        var distanceAlongMeters: Double
        var distanceRemainingMeters: Double
        var timeRemainingSeconds: Double
        var distanceToManeuverMeters: Double
        var upcomingManeuverIndex: Int?
        var followingManeuverIndex: Int?
        var arrived: Bool
        var offRoute: Bool
    }

    static func evaluate(
        latitude: Double,
        longitude: Double,
        coordinates: [(latitude: Double, longitude: Double)],
        maneuvers: [RouteManeuver],
        durationSeconds: Double
    ) -> Snapshot {
        guard coordinates.count >= 2 else {
            return Snapshot(
                distanceFromLineMeters: 0,
                distanceAlongMeters: 0,
                distanceRemainingMeters: 0,
                timeRemainingSeconds: 0,
                distanceToManeuverMeters: 0,
                upcomingManeuverIndex: nil,
                followingManeuverIndex: nil,
                arrived: false,
                offRoute: false
            )
        }

        let here = (latitude: latitude, longitude: longitude)
        let cumulative = distances(along: coordinates)
        let total = cumulative[cumulative.count - 1]
        var bestDistance = Double.greatestFiniteMagnitude
        var bestAlong = 0.0
        var bestSegment = 0
        var bestFraction = 0.0
        var matched = false
        var prefix = 0.0

        for index in 0..<(coordinates.count - 1) {
            let start = coordinates[index]
            let end = coordinates[index + 1]
            let segment = cumulative[index + 1] - cumulative[index]
            if segment >= 0.5 {
                let projection = project(here, from: start, to: end)
                let along = prefix + min(segment, projection.along)
                if !matched || projection.distance + 0.5 < bestDistance || (abs(projection.distance - bestDistance) <= 0.5 && along > bestAlong) {
                    matched = true
                    bestDistance = projection.distance
                    bestAlong = along
                    bestSegment = index
                    bestFraction = min(1, max(0, projection.along / segment))
                }
            }
            prefix += segment
        }

        if !matched {
            bestDistance = meters(from: here, to: coordinates[0])
        }

        let remaining = max(0, total - bestAlong)
        let destination = coordinates[coordinates.count - 1]
        let arrived = meters(from: here, to: destination) <= arrivalMeters || (total > 1 && remaining <= arrivalMeters)
        let shapePosition = Double(bestSegment) + bestFraction
        let ahead = maneuvers.firstIndex { Double($0.beginShapeIndex) > shapePosition + 0.02 }
        let destinationIndex = maneuvers.lastIndex { [4, 5, 6].contains($0.type) }
        let maneuverIndex = ahead ?? destinationIndex
        let distanceToManeuver: Double
        if let ahead, let maneuverIndex, maneuverIndex == ahead {
            let targetIndex = min(max(maneuvers[maneuverIndex].beginShapeIndex, 0), cumulative.count - 1)
            distanceToManeuver = max(0, cumulative[targetIndex] - bestAlong)
        } else {
            distanceToManeuver = remaining
        }
        let following = maneuverIndex.flatMap { index -> Int? in
            let next = maneuvers.index(after: index)
            guard next < maneuvers.endIndex else { return nil }
            return next
        }

        return Snapshot(
            distanceFromLineMeters: bestDistance,
            distanceAlongMeters: bestAlong,
            distanceRemainingMeters: remaining,
            timeRemainingSeconds: timeRemaining(
                distanceAlong: bestAlong,
                total: total,
                shapePosition: shapePosition,
                maneuvers: maneuvers,
                cumulative: cumulative,
                durationSeconds: durationSeconds
            ),
            distanceToManeuverMeters: distanceToManeuver,
            upcomingManeuverIndex: maneuverIndex,
            followingManeuverIndex: following,
            arrived: arrived,
            offRoute: !arrived && bestDistance > offRouteMeters
        )
    }

    static func labelCoordinate(
        coordinates: [(latitude: Double, longitude: Double)],
        slot: Int,
        count: Int
    ) -> (latitude: Double, longitude: Double)? {
        guard coordinates.count >= 2 else { return nil }
        let fraction: Double
        if count <= 1 {
            fraction = 0.5
        } else {
            let start = 0.35
            let end = 0.72
            fraction = start + (end - start) * Double(slot) / Double(max(count - 1, 1))
        }
        return coordinate(at: fraction, coordinates: coordinates)
    }

    /// Cuts the route at the driven distance. Both pieces include the cut so the lines meet.
    static func split(
        coordinates: [(latitude: Double, longitude: Double)],
        distanceAlongMeters: Double
    ) -> (traveled: [(latitude: Double, longitude: Double)], remaining: [(latitude: Double, longitude: Double)]) {
        guard coordinates.count >= 2 else { return (coordinates, coordinates) }
        let cumulative = distances(along: coordinates)
        let total = cumulative[cumulative.count - 1]
        let target = min(max(distanceAlongMeters, 0), total)
        guard total > 0, let index = cumulative.lastIndex(where: { $0 <= target }), index < coordinates.count - 1 else {
            return (coordinates, [coordinates[coordinates.count - 1]])
        }
        let span = cumulative[index + 1] - cumulative[index]
        let portion = span > 0 ? (target - cumulative[index]) / span : 0
        let start = coordinates[index]
        let end = coordinates[index + 1]
        let cut = (
            latitude: start.latitude + (end.latitude - start.latitude) * portion,
            longitude: start.longitude + (end.longitude - start.longitude) * portion
        )
        var traveled = Array(coordinates.prefix(index + 1))
        if traveled.last?.latitude != cut.latitude || traveled.last?.longitude != cut.longitude {
            traveled.append(cut)
        }
        var remaining = [cut]
        remaining.append(contentsOf: coordinates.suffix(from: index + 1))
        return (traveled, remaining)
    }

    static func bearing(along coordinates: [(latitude: Double, longitude: Double)]) -> Double {
        guard coordinates.count >= 2 else { return 0 }
        return bearing(from: coordinates[0], to: coordinates[1])
    }

    static func bearing(
        from start: (latitude: Double, longitude: Double),
        to end: (latitude: Double, longitude: Double)
    ) -> Double {
        let lat1 = start.latitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let delta = (end.longitude - start.longitude) * .pi / 180
        let y = sin(delta) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(delta)
        let degrees = atan2(y, x) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }

    static func offset(
        latitude: Double,
        longitude: Double,
        bearingDegrees: Double,
        meters distance: Double
    ) -> (latitude: Double, longitude: Double) {
        let bearing = bearingDegrees * .pi / 180
        let north = distance * cos(bearing)
        let east = distance * sin(bearing)
        let latScale = 110_540.0
        let lonScale = max(1, 111_320.0 * cos(latitude * .pi / 180))
        return (latitude: latitude + north / latScale, longitude: longitude + east / lonScale)
    }

    static func spokenDistance(_ meters: Double) -> String {
        let miles = meters / 1609.344
        if miles >= 0.2 {
            return String(format: "In %.1f miles", locale: Locale(identifier: "en_US_POSIX"), miles)
        }
        let feet = max(50, Int((meters * 3.28084 / 50).rounded()) * 50)
        return "In \(feet) feet"
    }

    static func symbolName(for type: Int) -> String {
        switch type {
        case 2, 9, 10, 11, 18, 20, 23, 37:
            return "arrow.turn.up.right"
        case 3, 14, 15, 16, 19, 21, 24, 38:
            return "arrow.turn.up.left"
        case 12:
            return "arrow.uturn.right"
        case 13:
            return "arrow.uturn.left"
        case 4, 5, 6:
            return "flag.checkered"
        case 25:
            return "arrow.merge"
        case 26, 27:
            return "arrow.triangle.turn.up.right.circle"
        default:
            return "arrow.up"
        }
    }

    static func turnDistance(_ meters: Double) -> String {
        if meters >= 160.934 {
            let miles = meters / 1609.344
            if miles >= 10 {
                return String(format: "%.0f mi", locale: Locale(identifier: "en_US_POSIX"), miles)
            }
            return String(format: "%.1f mi", locale: Locale(identifier: "en_US_POSIX"), miles)
        }
        let feet = max(50, Int((meters * 3.28084 / 50).rounded()) * 50)
        return "\(feet) ft"
    }

    private static func timeRemaining(
        distanceAlong: Double,
        total: Double,
        shapePosition: Double,
        maneuvers: [RouteManeuver],
        cumulative: [Double],
        durationSeconds: Double
    ) -> Double {
        guard total > 1 else { return 0 }
        let proportional = durationSeconds * max(0, total - distanceAlong) / total
        guard !maneuvers.isEmpty else { return proportional }
        let current = maneuvers.lastIndex { Double($0.beginShapeIndex) <= shapePosition + 0.001 } ?? maneuvers.startIndex
        var time = 0.0
        for index in maneuvers.indices where index >= current {
            let step = maneuvers[index]
            let startAlong = cumulative[min(max(step.beginShapeIndex, 0), cumulative.count - 1)]
            let endAlong = cumulative[min(max(step.endShapeIndex, 0), cumulative.count - 1)]
            let span = max(0, endAlong - startAlong)
            if index == current {
                let left = max(0, endAlong - distanceAlong)
                if span > 1 {
                    time += step.timeSeconds * min(1, left / span)
                } else if left > 0 {
                    time += step.timeSeconds
                }
            } else {
                time += step.timeSeconds
            }
        }
        return time > 0 ? time : proportional
    }

    private static func coordinate(
        at fraction: Double,
        coordinates: [(latitude: Double, longitude: Double)]
    ) -> (latitude: Double, longitude: Double)? {
        let cumulative = distances(along: coordinates)
        let total = cumulative[cumulative.count - 1]
        guard total > 0 else { return coordinates.first }
        let target = total * min(max(fraction, 0), 1)
        guard let index = cumulative.lastIndex(where: { $0 <= target }), index < coordinates.count - 1 else {
            return coordinates.last
        }
        let span = cumulative[index + 1] - cumulative[index]
        let portion = span > 0 ? (target - cumulative[index]) / span : 0
        let start = coordinates[index]
        let end = coordinates[index + 1]
        return (
            latitude: start.latitude + (end.latitude - start.latitude) * portion,
            longitude: start.longitude + (end.longitude - start.longitude) * portion
        )
    }

    private static func distances(along coordinates: [(latitude: Double, longitude: Double)]) -> [Double] {
        var cumulative = [0.0]
        for index in 1..<coordinates.count {
            cumulative.append(cumulative[index - 1] + meters(from: coordinates[index - 1], to: coordinates[index]))
        }
        return cumulative
    }

    private static func project(
        _ point: (latitude: Double, longitude: Double),
        from start: (latitude: Double, longitude: Double),
        to end: (latitude: Double, longitude: Double)
    ) -> (along: Double, distance: Double) {
        let latScale = 110_540.0
        let lonScale = 111_320.0 * cos(start.latitude * .pi / 180)
        let east = (end.longitude - start.longitude) * lonScale
        let north = (end.latitude - start.latitude) * latScale
        let pointEast = (point.longitude - start.longitude) * lonScale
        let pointNorth = (point.latitude - start.latitude) * latScale
        let lengthSquared = east * east + north * north
        let portion = lengthSquared > 0 ? min(1, max(0, (pointEast * east + pointNorth * north) / lengthSquared)) : 0
        let projectedEast = east * portion
        let projectedNorth = north * portion
        return (
            along: hypot(projectedEast, projectedNorth),
            distance: hypot(pointEast - projectedEast, pointNorth - projectedNorth)
        )
    }

    private static func meters(
        from start: (latitude: Double, longitude: Double),
        to end: (latitude: Double, longitude: Double)
    ) -> Double {
        let latScale = 110_540.0
        let lonScale = 111_320.0 * cos(start.latitude * .pi / 180)
        let east = (end.longitude - start.longitude) * lonScale
        let north = (end.latitude - start.latitude) * latScale
        return hypot(east, north)
    }
}
