import SwiftUI

struct FloodStatusView: View {
    var place: String
    var floodActive: Bool
    var headline: String
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(place)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(floodActive ? "Flood alert" : "No flood alert")
                .font(.headline)
                .foregroundStyle(floodActive ? Color.red : Color.primary)
            Text(headline)
                .font(.subheadline)
                .lineLimit(2)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(floodActive ? "Flood alert in \(place). \(headline). Estimated exposure, not a road closure." : "No flood warning or advisory in \(place).")
    }
}

enum FloodStatusText {
    static func headline(_ alerts: CityAlerts) -> String {
        if let first = alerts.alerts.first { return first }
        if alerts.floodActive { return "A flood warning or advisory is active." }
        return "No flood warning or advisory."
    }

    static func detail(_ alerts: CityAlerts) -> String {
        var parts: [String] = []
        if let forecast = alerts.forecast { parts.append(forecast) }
        if let temperature = alerts.temperatureF {
            parts.append("\(Int(temperature.rounded()))°F")
        }
        parts.append("Not a road closure.")
        return parts.joined(separator: " · ")
    }
}
