import ActivityKit
import SwiftUI
import WidgetKit

struct TripLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripActivityAttributes.self) { context in
            LiveActivityLockScreen(context: context)
                .padding(12)
                .activityBackgroundTint(Color.black.opacity(0.2))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.origin).font(.caption).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.minutes) min").font(.headline)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.summary).font(.caption).lineLimit(2)
                    Text("Not a closure.").font(.caption2)
                }
            } compactLeading: {
                Text("\(context.state.minutes)m")
            } compactTrailing: {
                Image(systemName: "water.waves")
            } minimal: {
                Image(systemName: "water.waves")
            }
        }
        .supplementalActivityFamilies([.small])
    }
}

private struct LiveActivityLockScreen: View {
    @Environment(\.activityFamily) private var activityFamily
    var context: ActivityViewContext<TripActivityAttributes>

    var body: some View {
        if activityFamily == .small {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(context.state.minutes) min")
                    .font(.headline)
                Text("Not a closure")
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(context.attributes.origin) to \(context.attributes.destination)")
                    .font(.headline)
                    .lineLimit(1)
                Text("\(context.state.minutes) min")
                    .font(.title3.weight(.semibold))
                Text(context.state.summary)
                    .font(.caption)
                    .lineLimit(2)
                Text("Not a closure.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
