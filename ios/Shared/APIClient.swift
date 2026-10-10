import Foundation

struct APIError: Error, Equatable {
    var message: String
}

private struct ExplainBody: Encodable {
    var facts: JSONValue
    var language: String
}

private struct PrepareBody: Encodable {
    var location: Place?
    var notes: String
    var people: Int?
    var pets: Bool
    var mobility: String
    var medical: String
    var language: String
}

private struct AssistBody: Encodable {
    var location: Place
    var needs: [String]
    var language: String
}

private struct PlanBody: Encodable {
    var age: Int
    var interests: [String]
    var budget: String
    var vibe: String
    var start: Place
    var day: String?
    var needs: [String]
    var language: String
}

enum APIConfig {
    static var baseURL: URL {
        let raw = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String
        return URL(string: raw ?? "https://humanity-miami.web.app") ?? URL(string: "https://humanity-miami.web.app")!
    }
}

struct APIClient: Sendable {
    var baseURL: URL
    var session: URLSession

    init(baseURL: URL = APIConfig.baseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func alerts(lat: Double? = nil, lng: Double? = nil, language: String = "en") async throws -> CityAlerts {
        guard var components = URLComponents(url: baseURL.appending(path: "api/alerts"), resolvingAgainstBaseURL: false) else {
            throw APIError(message: "The alerts address is invalid.")
        }
        var items = [URLQueryItem(name: "language", value: language)]
        if let lat, let lng {
            items.append(URLQueryItem(name: "lat", value: String(lat)))
            items.append(URLQueryItem(name: "lng", value: String(lng)))
        }
        components.queryItems = items
        guard let url = components.url else { throw APIError(message: "The alerts address is invalid.") }
        let request = URLRequest(url: url, timeoutInterval: 20)
        let (data, response) = try await session.data(for: request)
        try throwIfNeeded(data: data, response: response)
        return try APICoding.decoder.decode(CityAlerts.self, from: data)
    }

    func prepare(location: Place?, notes: String, people: Int?, pets: Bool, mobility: String, medical: String, language: String) async throws -> PrepareResult {
        try await post(
            path: "api/prepare",
            body: PrepareBody(location: location, notes: notes, people: people, pets: pets, mobility: mobility, medical: medical, language: language),
            timeout: 55,
            as: PrepareResult.self
        )
    }

    func assist(location: Place, needs: [String], language: String) async throws -> AssistResult {
        try await post(
            path: "api/assist",
            body: AssistBody(location: location, needs: needs, language: language),
            timeout: 40,
            as: AssistResult.self
        )
    }

    func planDay(age: Int, interests: [String], budget: String, vibe: String, start: Place, day: Date?, needs: [String], language: String) async throws -> DayPlan {
        try await post(
            path: "api/plan",
            body: PlanBody(
                age: age,
                interests: interests,
                budget: budget,
                vibe: vibe,
                start: start,
                day: day.map(APIClient.miamiNaiveTimestamp),
                needs: needs,
                language: language
            ),
            timeout: 70,
            as: DayPlan.self
        )
    }

    func routes(origin: Place, destination: Place, departAt: Date?) async throws -> Trip {
        var body: [String: JSONValue] = [
            "origin": .object([
                "label": .string(origin.label),
                "lat": .number(origin.lat),
                "lng": .number(origin.lng),
            ]),
            "destination": .object([
                "label": .string(destination.label),
                "lat": .number(destination.lat),
                "lng": .number(destination.lng),
            ]),
        ]
        if let departAt {
            body["depart_at"] = .string(Self.miamiNaiveTimestamp(departAt))
        }
        return try await post(path: "api/routes", body: JSONValue.object(body), timeout: 25, as: Trip.self)
    }

    func explain(facts: JSONValue, language: String = "en") async throws -> ExplainResult {
        try await post(path: "api/explain", body: ExplainBody(facts: facts, language: language), timeout: 55, as: ExplainResult.self)
    }

    private func post<T: Decodable, Body: Encodable>(path: String, body: Body, timeout: TimeInterval, as type: T.Type) async throws -> T {
        var request = URLRequest(url: baseURL.appending(path: path), timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try APICoding.encoder.encode(body)
        let (data, response) = try await session.data(for: request)
        try throwIfNeeded(data: data, response: response)
        return try APICoding.decoder.decode(T.self, from: data)
    }

    private func throwIfNeeded(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError(message: "The route service did not respond.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError(message: Self.message(from: data, status: http.statusCode))
        }
    }

    static func message(from data: Data, status: Int) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let detail = object["detail"] as? String, !detail.isEmpty {
            return detail
        }
        return "Request failed (\(status))."
    }

    /// Naive timestamps are read as Miami local time by the API.
    static func miamiNaiveTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.string(from: date)
    }
}
