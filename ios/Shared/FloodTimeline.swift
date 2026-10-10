import RelevanceKit
import SwiftUI
import WidgetKit

struct FloodEntry: TimelineEntry {
    var date: Date
    var alerts: CityAlerts?
    var failed: Bool
}

struct FloodProvider: TimelineProvider {
    func placeholder(in context: Context) -> FloodEntry {
        FloodEntry(date: .now, alerts: nil, failed: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (FloodEntry) -> Void) {
        Task { completion(await Self.load()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FloodEntry>) -> Void) {
        Task {
            let entry = await Self.load()
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
        }
    }

    func relevance() async -> WidgetRelevance<Void> {
        let alerts = try? await APIClient().alerts()
        guard alerts?.floodActive == true else { return WidgetRelevance([]) }
        let interval = DateInterval(start: .now, duration: 60 * 60)
        return WidgetRelevance([
            WidgetRelevanceAttribute(context: .date(interval: interval, kind: .default)),
        ])
    }

    private static func load() async -> FloodEntry {
        do {
            return FloodEntry(date: .now, alerts: try await APIClient().alerts(), failed: false)
        } catch {
            return FloodEntry(date: .now, alerts: nil, failed: true)
        }
    }
}

struct FloodWidgetView: View {
    var entry: FloodEntry

    var body: some View {
        Group {
            if let alerts = entry.alerts {
                FloodStatusView(
                    place: alerts.place,
                    floodActive: alerts.floodActive,
                    headline: FloodStatusText.headline(alerts),
                    detail: FloodStatusText.detail(alerts)
                )
            } else if entry.failed {
                FloodStatusView(place: "Miami", floodActive: false, headline: "Weather could not be checked", detail: "Not a road closure.")
            } else {
                FloodStatusView(place: "Miami", floodActive: false, headline: "Checking flood alerts", detail: "Not a road closure.")
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}
