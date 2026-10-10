import AppIntents
import CoreSpotlight

struct CompareRoutesIntent: AppIntent {
    static var title: LocalizedStringResource = "Compare a flood-aware route"
    static var description = IntentDescription("Compare a typical drive with one that reduces mapped flood and event exposure in Miami.")
    static var openAppWhenRun = true

    @Parameter(title: "From") var origin: String
    @Parameter(title: "To") var destination: String
    @Parameter(title: "Depart") var departAt: Date?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trip = try await CompareRouteAction.perform(
            origin: origin,
            destination: destination,
            departAt: departAt,
            planner: TripPlanner.shared
        )
        TripStore.shared.show(trip)
        return .result(dialog: IntentDialog(stringLiteral: CompareRouteAction.dialog(origin: trip.origin.label, destination: trip.destination.label)))
    }
}

struct DescribeSelectedRouteIntent: AppIntent {
    static var title: LocalizedStringResource = "Describe this route"
    static var description = IntentDescription("Read the exposure note for the route on screen. It is estimated exposure, not a road closure.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let sentence = try DescribeRouteAction.sentence()
        return .result(dialog: IntentDialog(stringLiteral: sentence))
    }
}

struct MapMiamiShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CompareRoutesIntent(),
            phrases: [
                "Compare a flood-aware route in \(.applicationName)",
            ],
            shortTitle: "Compare route",
            systemImageName: "car.fill"
        )
        AppShortcut(
            intent: DescribeSelectedRouteIntent(),
            phrases: [
                "Describe this route in \(.applicationName)",
            ],
            shortTitle: "Describe route",
            systemImageName: "text.quote"
        )
    }
}

struct RecentTripEntity: IndexedEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Trip")
    static var defaultQuery = RecentTripQuery()

    var record: RecentTripRecord
    var id: String { record.id }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(record.origin) to \(record.destination)")
    }
}

struct RecentTripQuery: EntityStringQuery {
    func entities(for identifiers: [RecentTripEntity.ID]) async throws -> [RecentTripEntity] {
        RecentTripStore.all().filter { identifiers.contains($0.id) }.map(RecentTripEntity.init)
    }

    func entities(matching string: String) async throws -> [RecentTripEntity] {
        RecentTripStore.all().filter {
            $0.origin.localizedCaseInsensitiveContains(string) || $0.destination.localizedCaseInsensitiveContains(string)
        }.map(RecentTripEntity.init)
    }

    func suggestedEntities() async throws -> [RecentTripEntity] {
        RecentTripStore.all().map(RecentTripEntity.init)
    }
}

enum SpotlightIndexer {
    static func index(_ trip: Trip) async {
        let entity = RecentTripEntity(record: RecentTripRecord(origin: trip.origin.label, destination: trip.destination.label))
        try? await CSSearchableIndex.default().indexAppEntities([entity])
    }
}
