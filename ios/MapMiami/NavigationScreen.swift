import AVFoundation
import SwiftUI

struct ActiveNavigation: Equatable {
    var routeId: String
    var snapshot: RouteGuidance.Snapshot?
    var heading: Double
    var rerouting: Bool
    var locationProblem: String?
    var followsUser: Bool
    var userLatitude: Double?
    var userLongitude: Double?
}

struct ManeuverBanner: View {
    var navigation: ActiveNavigation
    var route: RouteCandidate?
    var destination: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if navigation.rerouting {
                Text("Rerouting…")
                    .font(.title3.weight(.semibold))
            } else if let problem = navigation.locationProblem, navigation.snapshot == nil {
                Text(problem)
                    .font(.subheadline)
            } else if navigation.snapshot == nil {
                Text("Locating you…")
                    .font(.title3.weight(.semibold))
            } else if navigation.snapshot?.arrived == true {
                Label("You have arrived", systemImage: "flag.checkered")
                    .font(.title3.weight(.semibold))
                Text(destination)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            } else if let snapshot = navigation.snapshot {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: symbol(for: snapshot))
                        .font(.title)
                        .frame(width: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(RouteGuidance.turnDistance(snapshot.distanceToManeuverMeters))
                            .font(.title2.weight(.bold))
                        Text(instruction(for: snapshot))
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let preview = following(for: snapshot) {
                    Text("Then \(preview)")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(2)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrandColor.navy, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var maneuvers: [RouteManeuver] {
        route?.maneuvers ?? []
    }

    private func instruction(for snapshot: RouteGuidance.Snapshot) -> String {
        guard let index = snapshot.upcomingManeuverIndex, maneuvers.indices.contains(index) else {
            return "Continue to the destination"
        }
        return maneuvers[index].instruction
    }

    private func following(for snapshot: RouteGuidance.Snapshot) -> String? {
        guard let index = snapshot.followingManeuverIndex, maneuvers.indices.contains(index) else { return nil }
        return maneuvers[index].instruction
    }

    private func symbol(for snapshot: RouteGuidance.Snapshot) -> String {
        guard let index = snapshot.upcomingManeuverIndex, maneuvers.indices.contains(index) else {
            return "arrow.up"
        }
        return RouteGuidance.symbolName(for: maneuvers[index].type)
    }
}

struct NavigationStatusBar: View {
    var snapshot: RouteGuidance.Snapshot?
    var fallbackSeconds: Double
    var onEnd: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(RouteFormat.minutes(snapshot?.timeRemainingSeconds ?? fallbackSeconds))
                    .font(.title.weight(.bold))
                Text(arrival)
                    .font(.subheadline)
                Text(RouteFormat.miles(snapshot?.distanceRemainingMeters ?? 0))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
            }
            .foregroundStyle(.white)
            Spacer()
            Button("End", action: onEnd)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Color.red, in: Capsule())
                .buttonStyle(.plain)
                .accessibilityHint("Stops guidance and returns to the route comparison")
        }
        .padding(16)
        .background(BrandColor.navy, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var arrival: String {
        let seconds = snapshot?.timeRemainingSeconds ?? fallbackSeconds
        let eta = Date().addingTimeInterval(max(0, seconds))
        return eta.formatted(date: .omitted, time: .shortened)
    }
}

@MainActor
final class GuidanceSpeaker {
    private let synthesizer = AVSpeechSynthesizer()
    private var approached: Set<Int> = []
    private var announced: Set<Int> = []
    private var lastUpcoming: Int?
    private var announcedArrival = false

    func reset() {
        synthesizer.stopSpeaking(at: .immediate)
        approached.removeAll()
        announced.removeAll()
        lastUpcoming = nil
        announcedArrival = false
    }

    func update(snapshot: RouteGuidance.Snapshot, maneuvers: [RouteManeuver], destination: String) {
        if snapshot.arrived {
            if !announcedArrival {
                announcedArrival = true
                speak("You have arrived at \(destination).")
            }
            return
        }
        if let previous = lastUpcoming, let current = snapshot.upcomingManeuverIndex, previous != current {
            speakTurn(previous, maneuvers: maneuvers)
        }
        lastUpcoming = snapshot.upcomingManeuverIndex
        guard let index = snapshot.upcomingManeuverIndex, maneuvers.indices.contains(index) else {
            speakContinue(snapshot)
            return
        }
        let distance = snapshot.distanceToManeuverMeters
        if distance <= 80 {
            speakTurn(index, maneuvers: maneuvers)
        } else if distance <= 400, approached.insert(index).inserted {
            speak("\(RouteGuidance.spokenDistance(distance)), \(maneuvers[index].instruction)")
        }
    }

    private func speakContinue(_ snapshot: RouteGuidance.Snapshot) {
        let distance = snapshot.distanceRemainingMeters
        if distance <= 80 {
            if announced.insert(-1).inserted {
                speak("Continue to the destination.")
            }
        } else if distance <= 400, approached.insert(-1).inserted {
            speak("\(RouteGuidance.spokenDistance(distance)), continue to the destination.")
        }
    }

    private func speakTurn(_ index: Int, maneuvers: [RouteManeuver]) {
        guard maneuvers.indices.contains(index), announced.insert(index).inserted else { return }
        speak(maneuvers[index].instruction)
    }

    private func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }
}
