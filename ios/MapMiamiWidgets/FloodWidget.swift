import SwiftUI
import WidgetKit

struct FloodWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MiamiFlood", provider: FloodProvider()) { entry in
            FloodWidgetView(entry: entry)
                .widgetURL(URL(string: "mapmiami://open"))
        }
        .configurationDisplayName("Miami flood alert")
        .description("Shows whether a National Weather Service flood warning or advisory is active. This is not a road closure.")
        .supportedFamilies(FloodWidgetFamilies.current)
    }
}

enum FloodWidgetFamilies {
    /// Extra-large is offered where the system has that size, including iPad.
    /// `systemExtraLargePortrait` is an iOS 27 family this SDK still marks unavailable on iPhone.
    static var current: [WidgetFamily] {
        [.systemSmall, .systemMedium, .systemExtraLarge, .accessoryRectangular, .accessoryInline, .accessoryCircular]
    }
}
