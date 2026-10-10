import SwiftUI

@main
struct MapMiamiWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchStatusView()
        }
    }
}

struct WatchStatusView: View {
    @State private var alerts: CityAlerts?
    @State private var failed = false

    var body: some View {
        Group {
            if let alerts {
                FloodStatusView(
                    place: alerts.place,
                    floodActive: alerts.floodActive,
                    headline: FloodStatusText.headline(alerts),
                    detail: FloodStatusText.detail(alerts)
                )
            } else if failed {
                Text("Weather could not be checked.")
            } else {
                ZStack {
                    BrandColor.navy
                    SurviveLogo(drawing: true, showsWordmark: false)
                        .frame(width: 88, height: 88)
                }
            }
        }
        .padding()
        .task { await load() }
    }

    private func load() async {
        do {
            alerts = try await APIClient().alerts()
        } catch {
            failed = true
        }
    }
}
