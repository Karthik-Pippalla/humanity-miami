import SwiftUI

enum FeatureMode: String, CaseIterable, Identifiable {
    case drive
    case alerts
    case prepare
    case plan

    var id: String { rawValue }

    var title: String {
        switch self {
        case .drive: "Drive"
        case .alerts: "Alerts"
        case .prepare: "Prepare"
        case .plan: "Plan"
        }
    }

    var detail: String {
        switch self {
        case .drive: "Plan a flood-aware drive"
        case .alerts: "Official storm, rain, hurricane, and flood alerts"
        case .prepare: "Checklist and nearby emergency help"
        case .plan: "A timed Miami day from your preferences"
        }
    }
}

struct AlertsPanel: View {
    @Bindable var store: TripStore
    @State private var report: CityAlerts?
    @State private var message: String?
    @State private var loading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Official storm, heavy-rain, hurricane, and flood alerts for your location.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
            locationButton
            Button(loading ? "Loading alerts…" : "Show alerts here") {
                Task { await load() }
            }
            .buttonStyle(.borderedProminent)
            .tint(BrandColor.coral)
            .disabled(store.here == nil || loading)
            if let message {
                Text(message).font(.subheadline).foregroundStyle(.red)
            }
            if let report {
                Text(summary(report))
                    .font(.subheadline)
                if (report.advisories ?? []).isEmpty {
                    Text("No storm, heavy-rain, hurricane, or flood alert is active at this point.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
                ForEach(report.advisories ?? []) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(item.category.replacingOccurrences(of: "_", with: " "))\(item.isWatch ? " · watch" : "")")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BrandColor.coral)
                        Text(item.headline).font(.subheadline.weight(.semibold))
                        if let plain = item.plainLanguage, !plain.isEmpty {
                            Text(plain).font(.subheadline)
                        }
                        Text("The headline is the official National Weather Service text. The paragraph is an explanation.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(BrandColor.navy)
                }
                GapList(gaps: report.dataGaps ?? [])
                Text(report.notice).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var locationButton: some View {
        HStack {
            Button(store.here == nil ? "Use my location" : "Using current location") {
                store.sampleLocation()
            }
            Button("Downtown Miami") {
                store.here = Place(label: "Downtown Miami", lat: 25.7617, lng: -80.1918)
            }
        }
        .font(.subheadline.weight(.semibold))
    }

    private func load() async {
        guard let here = store.here else { return }
        loading = true
        message = nil
        defer { loading = false }
        do {
            report = try await APIClient().alerts(lat: here.lat, lng: here.lng, language: store.language)
        } catch let failure as APIError {
            message = failure.message
        } catch {
            message = "Weather alerts could not be loaded."
        }
    }

    private func summary(_ report: CityAlerts) -> String {
        var parts = [report.place]
        if let forecast = report.forecast { parts.append(forecast) }
        if let temperature = report.temperatureF { parts.append("\(Int(temperature.rounded()))°F") }
        return parts.joined(separator: " · ")
    }
}

struct PreparePanel: View {
    @Bindable var store: TripStore
    @State private var notes = ""
    @State private var people = 2
    @State private var pets = false
    @State private var mobility = ""
    @State private var medical = ""
    @State private var needs: Set<String> = []
    @State private var checklist: PrepareResult?
    @State private var help: AssistResult?
    @State private var message: String?
    @State private var loading: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("A Gemma 4 checklist from your notes and the alerts at your location.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
            Stepper("People: \(people)", value: $people, in: 1...12)
            Toggle("Pets at home", isOn: $pets)
            TextField("Mobility", text: $mobility, prompt: Text("Walker, wheelchair, limited stairs"))
                .textFieldStyle(.roundedBorder)
            TextField("Medical", text: $medical, prompt: Text("Daily medicine, oxygen, dialysis"))
                .textFieldStyle(.roundedBorder)
            TextField("Other notes", text: $notes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
            Button(loading == "prepare" ? "Preparing…" : "Build checklist") {
                Task { await prepare() }
            }
            .buttonStyle(.borderedProminent)
            .tint(BrandColor.coral)
            .disabled(loading != nil)
            if let checklist {
                ForEach(checklist.items) { item in
                    ChecklistCard(item: item)
                }
                Text(checklist.model.localizedCaseInsensitiveContains("gemma") ? "Gemma 4" : "Standard checklist")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                GapList(gaps: checklist.dataGaps)
                Text(checklist.notice).font(.caption).foregroundStyle(.secondary)
            }
            Text("Nearby emergency help")
                .font(.headline)
            Text("Hospitals and Miami-Dade emergency information for elderly residents, wheelchair users, and other needs.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
            NeedsPicker(needs: $needs)
            HStack {
                Button(store.here == nil ? "Use my location" : "Using current location") {
                    store.sampleLocation()
                }
                Button("Downtown Miami") {
                    store.here = Place(label: "Downtown Miami", lat: 25.7617, lng: -80.1918)
                }
            }
            .font(.subheadline.weight(.semibold))
            Button(loading == "assist" ? "Looking nearby…" : "Find nearby help") {
                Task { await findHelp() }
            }
            .buttonStyle(.bordered)
            .disabled(store.here == nil || loading != nil)
            if let help {
                ForEach(help.resources) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name).font(.subheadline.weight(.semibold))
                        Text(item.address).font(.caption).foregroundStyle(.secondary)
                        if let minutes = item.driveMinutes {
                            Text("\(RouteFormat.oneDecimal(minutes)) min\(item.estimated ? " · estimated" : "")")
                                .font(.caption)
                        }
                        Text(item.confirm).font(.caption)
                        Link("Official page", destination: URL(string: item.sourceUrl) ?? URL(string: "https://www.miamidade.gov/global/emergency/home.page")!)
                            .font(.caption.weight(.semibold))
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(BrandColor.navy)
                }
                ForEach(help.steps) { item in
                    Text("\(item.category). \(item.action)").font(.subheadline)
                }
                GapList(gaps: help.dataGaps)
                Text(help.notice).font(.caption).foregroundStyle(.secondary)
            }
            if let message {
                Text(message).font(.subheadline).foregroundStyle(.red)
            }
        }
    }

    private func prepare() async {
        loading = "prepare"
        message = nil
        defer { loading = nil }
        do {
            checklist = try await APIClient().prepare(
                location: store.here,
                notes: notes,
                people: people,
                pets: pets,
                mobility: mobility,
                medical: medical,
                language: store.language
            )
        } catch let failure as APIError {
            message = failure.message
        } catch {
            message = "The checklist could not be created."
        }
    }

    private func findHelp() async {
        guard let here = store.here else { return }
        loading = "assist"
        message = nil
        defer { loading = nil }
        do {
            help = try await APIClient().assist(location: here, needs: Array(needs).sorted(), language: store.language)
        } catch let failure as APIError {
            message = failure.message
        } catch {
            message = "Nearby resources could not be loaded."
        }
    }
}

struct PlanPanel: View {
    @Bindable var store: TripStore
    @State private var age = 30
    @State private var interests = "art, food"
    @State private var budget = "medium"
    @State private var vibe = "relaxed"
    @State private var day = Date()
    @State private var needs: Set<String> = []
    @State private var message: String?
    @State private var loading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tell Plan Miami who is visiting. Gemma 4 picks catalog stops, then drive times set the clock.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
            Stepper("Age: \(age)", value: $age, in: 1...120)
            TextField("Interests", text: $interests)
                .textFieldStyle(.roundedBorder)
            Picker("Budget", selection: $budget) {
                Text("Free").tag("free")
                Text("Low").tag("low")
                Text("Medium").tag("medium")
                Text("High").tag("high")
            }
            Picker("Vibe", selection: $vibe) {
                Text("Relaxed").tag("relaxed")
                Text("Lively").tag("lively")
                Text("Family").tag("family")
                Text("Outdoors").tag("outdoors")
                Text("Culture").tag("culture")
            }
            DatePicker("Day", selection: $day)
            NeedsPicker(needs: $needs)
            HStack {
                Button(store.here == nil ? "Use my location" : "Using current location") {
                    store.sampleLocation()
                }
                Button("Downtown Miami") {
                    store.here = Place(label: "Downtown Miami", lat: 25.7617, lng: -80.1918)
                }
            }
            .font(.subheadline.weight(.semibold))
            Button(loading ? "Planning the day…" : "Plan Miami") {
                Task { await plan() }
            }
            .buttonStyle(.borderedProminent)
            .tint(BrandColor.coral)
            .disabled(store.here == nil || loading)
            if let plan = store.dayPlan, store.featureMode == .plan {
                Text(plan.note).font(.subheadline)
                ForEach(Array(plan.stops.enumerated()), id: \.element.id) { index, stop in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(index + 1) · \(VisitClock.range(stop))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BrandColor.coral)
                        Text(stop.name).font(.subheadline.weight(.semibold))
                        Text(stop.why).font(.subheadline)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(BrandColor.navy)
                }
                Text(plan.model.localizedCaseInsensitiveContains("gemma") ? "Gemma 4" : "Miami catalog")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                GapList(gaps: plan.dataGaps)
                Text(plan.notice).font(.caption).foregroundStyle(.secondary)
            }
            if let message {
                Text(message).font(.subheadline).foregroundStyle(.red)
            }
        }
    }

    private func plan() async {
        guard let here = store.here else { return }
        loading = true
        message = nil
        defer { loading = false }
        let parsed = interests.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        do {
            let result = try await APIClient().planDay(
                age: age,
                interests: parsed,
                budget: budget,
                vibe: vibe,
                start: here,
                day: day,
                needs: Array(needs).sorted(),
                language: store.language
            )
            store.showPlan(result)
        } catch let failure as APIError {
            message = failure.message
        } catch {
            message = "Plan Miami could not build a day."
        }
    }
}

private struct NeedsPicker: View {
    @Binding var needs: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Needs").font(.caption.weight(.semibold)).foregroundStyle(BrandColor.coral)
            ForEach([("elderly", "Elderly"), ("wheelchair", "Wheelchair"), ("medical", "Medical"), ("no_car", "No car")], id: \.0) { id, label in
                Toggle(label, isOn: Binding(
                    get: { needs.contains(id) },
                    set: { on in
                        if on { needs.insert(id) } else { needs.remove(id) }
                    }
                ))
            }
        }
    }
}

private struct ChecklistCard: View {
    var item: ChecklistItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.category).font(.caption.weight(.semibold)).foregroundStyle(BrandColor.coral)
            Text(item.action).font(.subheadline.weight(.semibold))
            Text(item.why).font(.subheadline)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .foregroundStyle(BrandColor.navy)
    }
}

private struct GapList: View {
    var gaps: [String]

    var body: some View {
        ForEach(gaps, id: \.self) { gap in
            Text(GapCopy.text(for: gap)).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private enum VisitClock {
    static func range(_ stop: ItineraryStop) -> String {
        var text = "\(label(stop.arrival))–\(label(stop.leave))"
        if let minutes = stop.travelMinutes {
            text += " · \(RouteFormat.oneDecimal(minutes)) min drive"
        }
        return text
    }

    private static func label(_ value: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime]
        guard let date = parser.date(from: value) else { return value }
        return date.formatted(date: .omitted, time: .shortened)
    }
}
