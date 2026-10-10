import SwiftUI
import WidgetKit

struct WatchFloodWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MiamiFloodWatch", provider: FloodProvider()) { entry in
            FloodWidgetView(entry: entry)
        }
        .configurationDisplayName("Miami flood alert")
        .description("Shows whether a flood warning or advisory is active. This is not a road closure.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

@main
struct MapMiamiWatchWidgets: WidgetBundle {
    var body: some Widget {
        WatchFloodWidget()
    }
}
