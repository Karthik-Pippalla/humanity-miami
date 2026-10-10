import MapKit
import SwiftUI
import UIKit

struct PlaceSearchField: View {
    var title: String
    @Binding var place: Place?
    @State private var query = ""
    @State private var choosing = false
    @State private var searchError: String?
    @State private var completer = PlaceCompleter()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(BrandColor.coral)
                .textCase(.uppercase)
            TextField(title == "From" ? "Little Havana, or 25.76, -80.22" : "Miami Beach, or 25.79, -80.13", text: $query)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit {
                    Keyboard.hide()
                    Task { await chooseFirst() }
                }
            if !completer.results.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(completer.results.enumerated()), id: \.offset) { index, result in
                        Button {
                            Keyboard.hide()
                            Task { await choose(result) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.title)
                                    .foregroundStyle(.white)
                                if !result.subtitle.isEmpty {
                                    Text(result.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.65))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if index < completer.results.count - 1 {
                            Divider().overlay(Color.white.opacity(0.12))
                        }
                    }
                }
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityElement(children: .contain)
                .accessibilityLabel("\(title) suggestions")
            } else if let searchError {
                Text(searchError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onAppear {
            if query.isEmpty { query = place?.label ?? "" }
        }
        .onChange(of: query) { _, newValue in
            guard !choosing else {
                choosing = false
                return
            }
            searchError = nil
            if newValue == place?.label {
                completer.clear()
                return
            }
            place = nil
            if let parsed = PlaceParser.coordinate(newValue) {
                place = parsed
                completer.clear()
                return
            }
            completer.update(query: newValue)
        }
        .onChange(of: place?.label) { _, label in
            if let label, query != label { query = label }
        }
    }

    private func chooseFirst() async {
        if let first = completer.results.first {
            await choose(first)
            return
        }
        guard let match = try? await PlaceLookup.firstPlace(matching: query) else {
            searchError = "No places matched that search."
            return
        }
        apply(match)
    }

    private func choose(_ result: MKLocalSearchCompletion) async {
        do {
            let match = try await PlaceLookup.place(for: result)
            apply(match)
        } catch {
            searchError = "Could not use that place."
        }
    }

    private func apply(_ match: Place) {
        choosing = true
        place = match
        query = match.label
        completer.clear()
        Keyboard.hide()
    }
}

enum Keyboard {
    static func hide() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

@MainActor
@Observable
final class PlaceCompleter: NSObject, MKLocalSearchCompleterDelegate {
    private let completer = MKLocalSearchCompleter()
    var results: [MKLocalSearchCompletion] = []

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        completer.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 25.78, longitude: -80.2),
            span: MKCoordinateSpan(latitudeDelta: 1.2, longitudeDelta: 1.4)
        )
    }

    func update(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            results = []
            completer.queryFragment = ""
            return
        }
        completer.queryFragment = trimmed
    }

    func clear() {
        results = []
        completer.queryFragment = ""
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let next = Array(completer.results.prefix(6))
        Task { @MainActor in
            results = next
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            results = []
        }
    }
}

enum PlaceParser {
    static func coordinate(_ text: String) -> Place? {
        let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let lat = Double(parts[0]), let lng = Double(parts[1]) else { return nil }
        guard (-90...90).contains(lat), (-180...180).contains(lng) else { return nil }
        return Place(label: text, lat: lat, lng: lng)
    }
}

enum PlaceLookup {
    static func suggestions(matching query: String) async throws -> [Place] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.address, .pointOfInterest]
        request.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 25.78, longitude: -80.2),
            span: MKCoordinateSpan(latitudeDelta: 1.2, longitudeDelta: 1.4)
        )
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.prefix(5).map { item in
            Place(
                label: item.name ?? query,
                lat: item.location.coordinate.latitude,
                lng: item.location.coordinate.longitude
            )
        }
    }

    static func firstPlace(matching query: String) async throws -> Place {
        if let parsed = PlaceParser.coordinate(query) { return parsed }
        let matches = try await suggestions(matching: query)
        guard let first = matches.first else {
            throw APIError(message: "No place matched \(query) in South Florida.")
        }
        return first
    }

    static func place(for completion: MKLocalSearchCompletion) async throws -> Place {
        let response = try await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start()
        guard let item = response.mapItems.first else {
            throw APIError(message: "No place matched \(completion.title).")
        }
        let subtitle = completion.subtitle
        let label = subtitle.isEmpty ? (item.name ?? completion.title) : "\(completion.title), \(subtitle)"
        return Place(
            label: label,
            lat: item.location.coordinate.latitude,
            lng: item.location.coordinate.longitude
        )
    }
}

extension Place: Identifiable {
    var id: String { "\(label)|\(lat)|\(lng)" }
}
