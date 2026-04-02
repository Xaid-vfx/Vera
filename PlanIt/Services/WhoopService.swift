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
    private let apiBase   = "https://api.prod.whoop.com/developer/v1"
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
        guard let refresh = refreshToken else { throw URLError(.userAuthenticationRequired) }

        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type":    "refresh_token",
            "refresh_token": refresh,
            "client_id":     clientId,
            "client_secret": clientSecret,
        ].map { "\($0.key)=\($0.value)" }.joined(separator: "&")

        request.httpBody = body.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        accessToken  = token.access_token
        if let r = token.refresh_token { refreshToken = r }
    }

    // MARK: - Data Fetching
    func fetchData() async -> WhoopData? {
        guard isConnected, let token = accessToken else { return nil }

        do {
            async let recovery = fetchRecovery(token: token)
            async let sleep    = fetchSleep(token: token)
            async let cycle    = fetchCycle(token: token)
            return await WhoopData(recovery: try recovery, sleep: try sleep, cycle: try cycle)
        } catch {
            // Try refresh once
            do {
                try await refreshAccessToken()
                return await fetchData()
            } catch {
                appLogger.notice("[Whoop] Fetch failed: \(error.localizedDescription)")
                return nil
            }
        }
    }

    private func fetchRecovery(token: String) async throws -> WhoopRecoveryResponse {
        try await get("\(apiBase)/recovery?limit=1&nextToken=", token: token)
    }

    private func fetchSleep(token: String) async throws -> WhoopSleepResponse {
        try await get("\(apiBase)/sleep?limit=1", token: token)
    }

    private func fetchCycle(token: String) async throws -> WhoopCycleResponse {
        try await get("\(apiBase)/cycle?limit=1", token: token)
    }

    private func get<T: Decodable>(_ urlString: String, token: String) async throws -> T {
        var request = URLRequest(url: URL(string: urlString)!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(T.self, from: data)
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
        sleepPerformance = r?.sleep_performance_percentage
        hrv              = r?.hrv_rmssd_milli
        rhr              = r?.resting_heart_rate
        strainScore      = cycle.records.first?.score?.strain
    }
}

private struct TokenResponse: Codable {
    let access_token: String
    let refresh_token: String?
}

struct WhoopRecoveryResponse: Codable {
    let records: [WhoopRecovery]
}
struct WhoopRecovery: Codable {
    let score: WhoopRecoveryScore?
}
struct WhoopRecoveryScore: Codable {
    let recovery_score: Int?
    let sleep_performance_percentage: Int?
    let hrv_rmssd_milli: Double?
    let resting_heart_rate: Double?
}

struct WhoopSleepResponse: Codable {
    let records: [WhoopSleep]
}
struct WhoopSleep: Codable {
    let score: WhoopSleepScore?
}
struct WhoopSleepScore: Codable {
    let sleep_performance_percentage: Int?
}

struct WhoopCycleResponse: Codable {
    let records: [WhoopCycle]
}
struct WhoopCycle: Codable {
    let score: WhoopCycleScore?
}
struct WhoopCycleScore: Codable {
    let strain: Double?
}
