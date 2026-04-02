import Foundation
import AuthenticationServices

/// Handles Google OAuth2 and Google Calendar API (read events + create events).
@MainActor
final class GoogleCalendarService: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {

    // MARK: - Published state
    @Published var isConnected: Bool = false
    @Published var isLoading: Bool = false
    @Published var error: String?

    // MARK: - Constants
    private let authURL     = "https://accounts.google.com/o/oauth2/v2/auth"
    private let tokenURL    = "https://oauth2.googleapis.com/token"
    private let apiBase     = "https://www.googleapis.com/calendar/v3"
    // iOS OAuth clients use reversed client ID as scheme — no redirect URI whitelist needed
    private let redirectURI    = "com.googleusercontent.apps.138948836297-qc0o6b349eepkpb47r86g55nfjri0a63:/"
    private let redirectScheme = "com.googleusercontent.apps.138948836297-qc0o6b349eepkpb47r86g55nfjri0a63"
    private let scopes      = "https://www.googleapis.com/auth/calendar.events"

    private let tokenKey        = "google_access_token"
    private let refreshTokenKey = "google_refresh_token"
    private let clientIdKey     = "google_client_id"

    // MARK: - Init
    override init() {
        super.init()
        if UserDefaults.standard.string(forKey: clientIdKey) == nil {
            UserDefaults.standard.set(APIKeys.googleClientId, forKey: clientIdKey)
        }
        isConnected = accessToken != nil
    }

    // MARK: - Credential storage
    var clientId: String {
        get { UserDefaults.standard.string(forKey: clientIdKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: clientIdKey) }
    }
    private var accessToken: String? {
        get { UserDefaults.standard.string(forKey: tokenKey) }
        set { UserDefaults.standard.set(newValue, forKey: tokenKey) }
    }
    private var refreshToken: String? {
        get { UserDefaults.standard.string(forKey: refreshTokenKey) }
        set { UserDefaults.standard.set(newValue, forKey: refreshTokenKey) }
    }

    // MARK: - OAuth Connect
    func connect() async {
        guard !clientId.isEmpty else {
            error = "Enter your Google Client ID in Settings first"
            return
        }
        isLoading = true
        error = nil

        var components = URLComponents(string: authURL)!
        components.queryItems = [
            .init(name: "client_id",      value: clientId),
            .init(name: "redirect_uri",   value: redirectURI),
            .init(name: "response_type",  value: "code"),
            .init(name: "scope",          value: scopes),
            .init(name: "access_type",    value: "offline"),
            .init(name: "prompt",         value: "consent"),
        ]

        guard let authorizationURL = components.url else {
            error = "Failed to build Google auth URL"
            isLoading = false
            return
        }

        do {
            let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
                let session = ASWebAuthenticationSession(
                    url: authorizationURL,
                    callbackURLScheme: self.redirectScheme
                ) { url, err in
                    if let err { continuation.resume(throwing: err) }
                    else if let url { continuation.resume(returning: url) }
                    else { continuation.resume(throwing: URLError(.badURL)) }
                }
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = false
                session.start()
            }

            guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value else {
                throw URLError(.badServerResponse)
            }

            try await exchangeCode(code)
            isConnected = true
            appLogger.notice("[Google] Calendar connected successfully")

        } catch {
            self.error = error.localizedDescription
            appLogger.notice("[Google] Auth error: \(error.localizedDescription)")
        }

        isLoading = false
    }

    func disconnect() {
        accessToken  = nil
        refreshToken = nil
        isConnected  = false
    }

    // MARK: - Token Exchange
    private func exchangeCode(_ code: String) async throws {
        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // iOS OAuth clients are public — no client_secret in the exchange
        let body = [
            "grant_type":   "authorization_code",
            "code":         code,
            "redirect_uri": redirectURI,
            "client_id":    clientId,
        ].map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
         .joined(separator: "&")

        request.httpBody = body.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        let token = try JSONDecoder().decode(GoogleTokenResponse.self, from: data)
        accessToken  = token.access_token
        if let r = token.refresh_token { refreshToken = r }
    }

    private func refreshAccessToken() async throws {
        guard let refresh = refreshToken else { throw URLError(.userAuthenticationRequired) }

        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type":    "refresh_token",
            "refresh_token": refresh,
            "client_id":     clientId,
        ].map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
         .joined(separator: "&")

        request.httpBody = body.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        let token = try JSONDecoder().decode(GoogleTokenResponse.self, from: data)
        accessToken = token.access_token
    }

    // MARK: - Read Events
    func fetchTodayEvents() async -> [CalendarEvent] {
        await fetchEvents(for: Date())
    }

    func fetchTomorrowEvents() async -> [CalendarEvent] {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return await fetchEvents(for: tomorrow)
    }

    private func fetchEvents(for day: Date) async -> [CalendarEvent] {
        guard isConnected, let token = accessToken else { return [] }

        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: day)
        let endOfDay   = cal.date(byAdding: .day, value: 1, to: startOfDay)!

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        var components = URLComponents(string: "\(apiBase)/calendars/primary/events")!
        components.queryItems = [
            .init(name: "timeMin",      value: iso.string(from: startOfDay)),
            .init(name: "timeMax",      value: iso.string(from: endOfDay)),
            .init(name: "singleEvents", value: "true"),
            .init(name: "orderBy",      value: "startTime"),
            .init(name: "maxResults",   value: "20"),
        ]

        do {
            var request = URLRequest(url: components.url!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)

            if (response as? HTTPURLResponse)?.statusCode == 401 {
                try await refreshAccessToken()
                return await fetchEvents(for: day)
            }

            let result = try JSONDecoder().decode(GoogleCalendarEventList.self, from: data)
            return result.items.compactMap { CalendarEvent(from: $0) }
        } catch {
            appLogger.notice("[Google] Fetch events error: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Create Events (write back after planning)
    func createEvents(from tasks: [PlanTask], startingAt baseDate: Date = Date()) async {
        guard isConnected, let token = accessToken else { return }

        var cursor = Calendar.current.date(
            bySettingHour: Calendar.current.component(.hour, from: baseDate) < 9 ? 9 : Calendar.current.component(.hour, from: baseDate),
            minute: 0, second: 0, of: baseDate
        ) ?? baseDate

        for task in tasks {
            let end = cursor.addingTimeInterval(Double(task.duration) * 60)
            let event = GoogleEventBody(
                summary: task.title,
                description: "Created by PlanIt • \(task.category.rawValue) • \(task.priority.rawValue) priority",
                start: GoogleEventTime(dateTime: cursor),
                end: GoogleEventTime(dateTime: end)
            )

            do {
                var request = URLRequest(url: URL(string: "\(apiBase)/calendars/primary/events")!)
                request.httpMethod = "POST"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                request.httpBody = try encoder.encode(event)
                _ = try await URLSession.shared.data(for: request)
                appLogger.notice("[Google] Created event: \(task.title)")
            } catch {
                appLogger.notice("[Google] Create event error: \(error.localizedDescription)")
            }

            // Gap between tasks
            cursor = end.addingTimeInterval(15 * 60)
        }
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        ASPresentationAnchor()
    }
}

// MARK: - Google API models

private struct GoogleTokenResponse: Codable {
    let access_token: String
    let refresh_token: String?
}

private struct GoogleCalendarEventList: Codable {
    let items: [GoogleCalendarItem]
}

private struct GoogleCalendarItem: Codable {
    let id: String?
    let summary: String?
    let start: GoogleEventTime?
    let end: GoogleEventTime?
}

private struct GoogleEventTime: Codable {
    let dateTime: Date?
    let date: String?   // all-day events use date string

    init(dateTime: Date) {
        self.dateTime = dateTime
        self.date = nil
    }
}

private struct GoogleEventBody: Codable {
    let summary: String
    let description: String
    let start: GoogleEventTime
    let end: GoogleEventTime
}

// MARK: - CalendarEvent initializer from Google item

private extension CalendarEvent {
    init?(from item: GoogleCalendarItem) {
        guard let id = item.id, let title = item.summary else { return nil }

        let isAllDay = item.start?.dateTime == nil
        let start = item.start?.dateTime ?? Date()
        let end   = item.end?.dateTime ?? start.addingTimeInterval(3600)

        self.init(
            id: id,
            title: title,
            startDate: start,
            endDate: end,
            isAllDay: isAllDay,
            calendarName: "primary"
        )
    }
}
