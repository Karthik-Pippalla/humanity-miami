import SwiftUI

struct TripSheet: View {
    @Bindable var store: TripStore
    @State private var expanded = true

    var body: some View {
        VStack(spacing: 0) {
            grabber
            if expanded {
                ScrollView {
                    form
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
            } else {
                collapsedBar
            }
        }
        .frame(height: expanded ? (store.featureMode == .drive ? 420 : 560) : 92)
        .clipped()
        .animation(.smooth(duration: 0.25), value: expanded)
    }

    private var grabber: some View {
        Button {
            setExpanded(!expanded)
        } label: {
            VStack(spacing: 6) {
                Capsule()
                    .fill(Color.white.opacity(0.45))
                    .frame(width: 40, height: 5)
                Image(systemName: expanded ? "chevron.down" : "chevron.up")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            .padding(.bottom, expanded ? 0 : 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(expanded ? "Minimize the trip panel" : "Show the trip panel")
        .gesture(
            DragGesture(minimumDistance: 8).onEnded { value in
                if value.translation.height > 28 {
                    setExpanded(false)
                } else if value.translation.height < -28 {
                    setExpanded(true)
                }
            }
        )
    }

    private var collapsedBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.featureMode.title)
                    .font(.subheadline.weight(.semibold))
                Text(collapsedDetail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .contentShape(Rectangle())
        .onTapGesture { setExpanded(true) }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Shows the place fields and route comparison")
    }

    private var collapsedDetail: String {
        if store.featureMode != .drive {
            return store.featureMode.detail
        }
        guard let trip = store.trip, let route = trip.routes.first(where: { $0.id == store.selectedId }) ?? trip.recommended else {
            if store.origin != nil || store.destination != nil {
                return "\(store.origin?.label ?? "From") to \(store.destination?.label ?? "To")"
            }
            return "Plan a flood-aware drive"
        }
        return "\(route.label) · \(RouteFormat.minutes(route.durationSeconds))"
    }

    private func setExpanded(_ next: Bool) {
        if !next { Keyboard.hide() }
        expanded = next
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            modePicker
            languagePicker
            if store.featureMode == .drive {
                driveForm
            } else if store.featureMode == .alerts {
                AlertsPanel(store: store)
            } else if store.featureMode == .prepare {
                PreparePanel(store: store)
            } else {
                PlanPanel(store: store)
            }
        }
        .padding(16)
        .onChange(of: store.language) {
            Task { await store.reexplain() }
        }
    }

    private var modePicker: some View {
        Picker("Mode", selection: $store.featureMode) {
            ForEach(FeatureMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Feature")
    }

    private var languagePicker: some View {
        Picker("Language", selection: $store.language) {
            Text("English").tag("en")
            Text("Español").tag("es")
            Text("Kreyòl").tag("ht")
        }
        .pickerStyle(.segmented)
    }

    private var driveForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            PlaceSearchField(title: "From", place: $store.origin)
            PlaceSearchField(title: "To", place: $store.destination)
            DatePicker("Depart", selection: $store.depart)
                .font(.subheadline)
                .simultaneousGesture(TapGesture().onEnded { Keyboard.hide() })
            HStack {
                Button {
                    Keyboard.hide()
                    Task { await store.compare() }
                } label: {
                    Text(store.loading ? "Checking routes…" : "Compare routes")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(BrandColor.navy)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(BrandColor.coral, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .opacity(store.origin == nil || store.destination == nil || store.loading ? 0.5 : 1)
                .disabled(store.origin == nil || store.destination == nil || store.loading)
                Button("Demo") {
                    Keyboard.hide()
                    store.loadDemo()
                }
                    .buttonStyle(.bordered)
                    .tint(BrandColor.coral)
                    .disabled(store.loading)
            }
            Button("Use current location") {
                Keyboard.hide()
                store.useCurrentLocation()
            }
                .font(.subheadline)
            Text(store.trip?.notice ?? TripNotice.beforeRequest)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let errorMessage = store.errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
            if let trip = store.trip {
                ResultsList(
                    trip: trip,
                    selectedId: store.selectedId,
                    explaining: store.explaining,
                    explanation: store.explanation,
                    explainGaps: store.explainGaps,
                    onSelect: { store.select($0) },
                    onStart: { store.startNavigation(routeId: $0) }
                )
            }
            Text(APIConfig.baseURL.absoluteString)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            SurviveLogo()
            Text(store.featureMode == .drive ? "Flood-aware and event-aware driving" : store.featureMode.detail)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))
        }
    }
}

struct ResultsList: View {
    var trip: Trip
    var selectedId: String?
    var explaining: Bool
    var explanation: Explanation?
    var explainGaps: [String]
    var onSelect: (String) -> Void
    var onStart: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let weather = trip.weather {
                    WeatherBlock(weather: weather)
                }
                ForEach(trip.routes) { route in
                    RouteCard(
                        route: route,
                        origin: trip.origin,
                        destination: trip.destination,
                        recommended: route.id == trip.recommendedId,
                        selected: route.id == selectedId,
                        onSelect: { onSelect(route.id) },
                        onStart: { onStart(route.id) }
                    )
                    .routeAnnotation(
                        AnnotatedRoute(
                            id: route.id,
                            label: route.label,
                            summary: route.flood.summary,
                            minutes: RouteFormat.minutes(route.durationSeconds),
                            recommended: route.id == trip.recommendedId
                        ),
                        active: route.id == selectedId
                    )
                }
                ExplanationBlock(explaining: explaining, explanation: explanation, gaps: explainGaps)
                if !trip.dataGaps.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(trip.dataGaps, id: \.self) { gap in
                            Text(GapCopy.text(for: gap))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

private struct WeatherBlock: View {
    var weather: WeatherSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(headline)
                .font(.subheadline.weight(.medium))
            Text(weather.floodActive
                ? "Active flood alert. Mapped flood areas along the route are shown in blue."
                : "No active flood warning or advisory, so flood areas are hidden.")
                .font(.subheadline)
                .foregroundStyle(weather.floodActive ? Color.red : Color.secondary)
            ForEach(weather.alerts, id: \.self) { alert in
                Text(alert)
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var headline: String {
        var parts: [String] = []
        if let forecast = weather.forecast { parts.append(forecast) }
        if let temperature = weather.temperatureF { parts.append("\(Int(temperature.rounded()))°F") }
        return parts.isEmpty ? "Weather loaded" : parts.joined(separator: " · ")
    }
}

private struct RouteCard: View {
    var route: RouteCandidate
    var origin: Place
    var destination: Place
    var recommended: Bool
    var selected: Bool
    var onSelect: () -> Void
    var onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onSelect) {
                details
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            Button(action: onStart) {
                Text("Start")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(BrandColor.coral, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Starts guidance along this route")
            directionLinks
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            heading
            Text(route.flood.summary)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            eventLines
            Text(scoreLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: 1)
        }
    }

    private var heading: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(route.label).font(.headline)
                Text(recommended ? "Recommended" : "Alternate")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(RouteFormat.minutes(route.durationSeconds)).font(.title3.weight(.semibold))
                Text(RouteFormat.miles(route.distanceMeters))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var eventLines: some View {
        ForEach(route.events) { event in
            Text("\(event.name) at \(event.venue). \(event.inDepartureWindow ? "Overlaps this departure." : "Scheduled outside this departure window.")")
                .font(.subheadline)
                .multilineTextAlignment(.leading)
        }
    }

    @ViewBuilder
    private var directionLinks: some View {
        if let links = ExternalDirections.links(origin: origin, destination: destination, coordinates: route.coordinates) {
            HStack(spacing: 16) {
                Link("Apple Maps", destination: links.apple)
                Link("Google Maps", destination: links.google)
            }
            .font(.caption.weight(.semibold))
        }
    }

    private var scoreLine: String {
        let floodMinutes = Int((route.score.floodPenaltySeconds / 60).rounded())
        let eventMinutes = Int((route.score.eventPenaltySeconds / 60).rounded())
        var line = route.hasToll ? "Includes a toll. " : ""
        if floodMinutes > 0 || eventMinutes > 0 {
            line += "Score adds \(floodMinutes) min of flood-zone exposure"
            if eventMinutes > 0 { line += " and \(eventMinutes) min of event exposure" }
            line += ". Not a closure."
        } else {
            line += "Not a road closure."
        }
        return line
    }

    private var accessibilityLabel: String {
        "\(route.label), \(recommended ? "recommended" : "alternate"), \(RouteFormat.minutes(route.durationSeconds)). \(route.flood.summary) Not a road closure."
    }
}

private struct ExplanationBlock: View {
    var explaining: Bool
    var explanation: Explanation?
    var gaps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if explaining {
                Text("Explanation")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text("Writing the explanation…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if let explanation {
                Text(explanation.model.localizedCaseInsensitiveContains("gemma") ? "Gemma 4" : "Route scores")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(explanation.text)
                    .font(.subheadline)
                Text("This note describes the scores above. It does not calculate the route.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(gaps, id: \.self) { gap in
                Text(GapCopy.text(for: gap))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Registers the selected route as the on-screen entity Siri can describe.
    func routeAnnotation(_ route: AnnotatedRoute, active: Bool) -> some View {
        modifier(RouteAnnotationModifier(route: route, active: active))
    }
}

private struct RouteAnnotationModifier: ViewModifier {
    var route: AnnotatedRoute
    var active: Bool

    func body(content: Content) -> some View {
        content
            .accessibilityAddTraits(active ? .isSelected : [])
            .onAppear { if active { OnScreenRoutes.focus(route) } }
            .onChange(of: active) { _, isActive in
                if isActive { OnScreenRoutes.focus(route) }
            }
    }
}
