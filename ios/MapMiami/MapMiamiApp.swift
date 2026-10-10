import SwiftUI

@main
struct MapMiamiApp: App {
    @State private var store = TripStore.shared

    init() {
        TripPlanner.shared = LiveTripPlanner()
    }

    var body: some Scene {
        WindowGroup {
            MapScreen(store: store)
                .tint(BrandColor.coral)
                .onAppear { store.restoreHandoff() }
                .onOpenURL { url in
                    guard url.scheme == "mapmiami" else { return }
                    store.restoreHandoff()
                }
        }
    }
}
