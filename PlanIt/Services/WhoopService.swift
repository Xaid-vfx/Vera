import Foundation
import AuthenticationServices
import CryptoKit

/// Handles Whoop OAuth2 (PKCE) authentication and data fetching.
@MainActor
final class WhoopService: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {

    // MARK: - Published state
    @Published var isConnected: Bool = false
    @Published var isLoading: Bool = false
    @Published var error: String?

    // MARK: - Constants
    private let authURL   = "https://api.prod.whoop.com/oauth/oauth2/auth"
    private let tokenURL  = "https://api.prod.whoop.com/oauth/oauth2/token"
    private let apiBase   = "https://api.prod.whoop.com/developer/v2"
    private let redirectURI = "com.planit.app://oauth/whoop"
    private let scopes    = "read:recovery read:sleep read:cycles read:profile offline"

    private let tokenKey        = "whoop_access_token"
    private let refreshTokenKey = "whoop_refresh_token"
    private let clientIdKey     = "whoop_client_id"
    private let clientSecretKey = "whoop_client_secret"

    // MARK: - Init
    override init() {
        super.init()
        // Seed bundled credentials if nothing saved yet
        if UserDefaults.standard.string(forKey: clientIdKey) == nil {
            UserDefaults.standard.set(APIKeys.whoopClientId, forKey: clientIdKey)
        }
        if UserDefaults.standard.string(forKey: clientSecretKey) == nil {
            UserDefaults.standard.set(APIKeys.whoopClientSecret, forKey: clientSecretKey)
        }
        isConnected = accessToken != nil
    }

    // MARK: - Credential storage (UserDefaults — swap for Keychain in production)
    var clientId: String {
        get { UserDefaults.standard.string(forKey: clientIdKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: clientIdKey) }
    }
    var clientSecret: String {
        get { UserDefaults.standard.string(forKey: clientSecretKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: clientSecretKey) }
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
            error = "Enter your Whoop Client ID in Settings first"
            return
        }
        isLoading = true
        error = nil

        let verifier  = pkceVerifier()
        let challenge = pkceChallenge(for: verifier)
        let state     = UUID().uuidString

        var components = URLComponents(string: authURL)!
        components.queryItems = [
            .init(name: "client_id",             value: clientId),
            .init(name: "redirect_uri",           value: redirectURI),
            .init(name: "response_type",          value: "code"),
            .init(name: "scope",                  value: scopes),
            .init(name: "state",                  value: state),
            .init(name: "code_challenge",         value: challenge),
            .init(name: "code_challenge_method",  value: "S256"),
        ]

        guard let authorizationURL = components.url else {
            error = "Failed to build Whoop auth URL"
            isLoading = false
            return
        }

        do {
            let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
                let session = ASWebAuthenticationSession(
                    url: authorizationURL,
                    callbackURLScheme: "com.planit.app"
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

            try await exchangeCode(code, verifier: verifier)
            isConnected = true
            appLogger.notice("[Whoop] Connected successfully")

        } catch {
            self.error = error.localizedDescription
            appLogger.notice("[Whoop] Auth error: \(error.localizedDescription)")
        }

        isLoading = false
    }

    func disconnect() {
        accessToken  = nil
        refreshToken = nil
        isConnected  = false
    }

    // MARK: - Token Exchange
    private func exchangeCode(_ code: String, verifier: String) async throws {
        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type":    "authorization_code",
            "code":          code,
            "redirect_uri":  redirectURI,
            "client_id":     clientId,
            "client_secret": clientSecret,
            "code_verifier": verifier,
        ].map { "\($0.key)=\($0.value)" }.joined(separator: "&")

        request.httpBody = body.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        accessToken  = token.access_token
        refreshToken = token.refresh_token
    }

    private func refreshAccessToken() async throws {
        guard let refresh = refreshToken else {
            appLogger.notice("[Whoop] No refresh token stored — re-auth required")
            throw URLError(.userAuthenticationRequired)
        }

        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // Percent-encode each value individually to handle special chars in tokens
        func encode(_ s: String) -> String {
            s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
        }
        let bodyParts = [
            "grant_type=refresh_token",
            "refresh_token=\(encode(refresh))",
            "client_id=\(encode(clientId))",
            "client_secret=\(encode(clientSecret))",
        ]
        request.httpBody = bodyParts.joined(separator: "&").data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let rawBody = String(data: data, encoding: .utf8) ?? "<binary>"
        appLogger.notice("[Whoop] Refresh response HTTP \(status): \(rawBody)")

        do {
            let token = try JSONDecoder().decode(TokenResponse.self, from: data)
            accessToken  = token.access_token
            if let r = token.refresh_token { refreshToken = r }
            appLogger.notice("[Whoop] Token refreshed successfully")
        } catch {
            // If refresh failed with 4xx the token is dead — force re-auth
            if status == 400 || status == 401 {
                appLogger.notice("[Whoop] Refresh token expired — marking disconnected")
                accessToken  = nil
                refreshToken = nil
                isConnected  = false
            }
            throw error
        }
    }

    // MARK: - Data Fetching
    func fetchData() async -> WhoopData? {
        let hasToken = accessToken != nil
        let hasRefresh = refreshToken != nil
        appLogger.notice("[Whoop] fetchData — isConnected=\(self.isConnected) hasAccessToken=\(hasToken) hasRefreshToken=\(hasRefresh)")
        guard isConnected else {
            appLogger.notice("[Whoop] Skipping fetch — not connected")
            return nil
        }

        // Try with current token, refresh once on 401
        for attempt in 1...2 {
            guard let token = accessToken else { return nil }
            do {
                async let recovery = fetchRecovery(token: token)
                async let sleep    = fetchSleep(token: token)
                async let cycle    = fetchCycle(token: token)
                let data = try await WhoopData(recovery: recovery, sleep: sleep, cycle: cycle)
                let rec = data.recoveryScore.map { "\($0)" } ?? "nil"
                let str = data.strainScore.map { "\($0)" } ?? "nil"
                appLogger.notice("[Whoop] Fetched data — recovery: \(rec), strain: \(str)")
                return data
            } catch URLError.userAuthenticationRequired where attempt == 1 {
                appLogger.notice("[Whoop] 401 — refreshing token")
                do { try await refreshAccessToken() } catch {
                    appLogger.notice("[Whoop] Token refresh failed: \(error.localizedDescription)")
                    return nil
                }
            } catch {
                appLogger.notice("[Whoop] Fetch failed: \(error.localizedDescription)")
                return nil
            }
        }
        return nil
    }

    private func fetchRecovery(token: String) async throws -> WhoopRecoveryResponse {
        try await get("\(apiBase)/recovery?limit=1", token: token)
    }

    private func fetchSleep(token: String) async throws -> WhoopSleepResponse {
        try await get("\(apiBase)/activity/sleep?limit=1", token: token)
    }

    private func fetchCycle(token: String) async throws -> WhoopCycleResponse {
        try await get("\(apiBase)/cycle?limit=1", token: token)
    }

    // V2 recovery comes embedded in cycle — but also available standalone at /v2/recovery

    private func get<T: Decodable>(_ urlString: String, token: String) async throws -> T {
        var request = URLRequest(url: URL(string: urlString)!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 {
            throw URLError(.userAuthenticationRequired)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            appLogger.notice("[Whoop] HTTP \(status) decode error for \(urlString): \(body)")
            throw error
        }
    }

    // MARK: - PKCE
    private func pkceVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func pkceChallenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        ASPresentationAnchor()
    }
}

// MARK: - Whoop response models

struct WhoopData {
    var recoveryScore: Int?
    var strainScore: Double?
    var sleepPerformance: Int?
    var hrv: Double?
    var rhr: Double?

    init(recovery: WhoopRecoveryResponse, sleep: WhoopSleepResponse, cycle: WhoopCycleResponse) {
        let r = recovery.records.first?.score
        recoveryScore    = r?.recovery_score
        hrv              = r?.hrv_rmssd_milli
        rhr              = r?.resting_heart_rate
        let s = sleep.records.first?.score
        sleepPerformance = s?.sleep_performance_percentage
        strainScore      = cycle.records.first?.score?.strain
    }
}

private struct TokenResponse: Codable {
    let access_token: String
    let refresh_token: String?
}

// V2 collection responses wrap records in a `records` array
struct WhoopRecoveryResponse: Codable {
    let records: [WhoopRecovery]
}
struct WhoopRecovery: Codable {
    let score: WhoopRecoveryScore?
}
struct WhoopRecoveryScore: Codable {
    let recovery_score: Int?
    let resting_heart_rate: Double?
    let hrv_rmssd_milli: Double?
    let spo2_percentage: Double?
    let skin_temp_celsius: Double?
}

struct WhoopSleepResponse: Codable {
    let records: [WhoopSleep]
}
struct WhoopSleep: Codable {
    let score: WhoopSleepScore?
}
struct WhoopSleepScore: Codable {
    let sleep_performance_percentage: Int?
    let sleep_consistency_percentage: Int?
    let sleep_efficiency_percentage: Int?
    let respiratory_rate: Double?
    let stage_summary: WhoopSleepStageSummary?
}
struct WhoopSleepStageSummary: Codable {
    let total_rem_sleep_time_milli: Int?
    let total_slow_wave_sleep_time_milli: Int?
    let total_light_sleep_time_milli: Int?
    let total_awake_time_milli: Int?
}

struct WhoopCycleResponse: Codable {
    let records: [WhoopCycle]
}
struct WhoopCycle: Codable {
    let score: WhoopCycleScore?
}
struct WhoopCycleScore: Codable {
    let strain: Double?
    let kilojoule: Double?
    let average_heart_rate: Int?
}
