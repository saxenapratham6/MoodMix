import CryptoKit
import Foundation

/// Opens the Spotify consent page and returns the redirect URL it lands on.
/// macOS uses a loopback server; iOS will use ASWebAuthenticationSession.
public protocol AuthCodeProvider: Sendable {
    var redirectURI: URL { get }
    func authorize(url: URL) async throws -> URL
}

public enum SpotifyError: LocalizedError {
    case notLoggedIn
    case missingClientID
    case authFailed(String)
    case noActiveDevice
    case http(Int, String)
    case restricted
    case notResponding
    case rateLimited(until: Date)

    public var errorDescription: String? {
        switch self {
        case .notLoggedIn: "Log in to Spotify first."
        case .missingClientID: "Add your Spotify Client ID in Settings."
        case .authFailed(let why): "Spotify login failed: \(why)"
        case .noActiveDevice: "Open Spotify on any device (this Mac, your phone…) so MoodMix has something to play on."
        case .http(let code, let message): "Spotify said no (\(code)): \(message.prefix(160))"
        case .notResponding: "Spotify on this device isn't responding to MoodMix. Quit Spotify (⌘Q), open it again, and press play once in Spotify."
        case .restricted: "Spotify didn't allow that right now. It may be an ad, a device that limits control, or nothing left to skip to."
        case .rateLimited(let until):
            "Spotify asked MoodMix to slow down. It'll pick up again automatically at \(until.formatted(date: .omitted, time: .shortened))."
        }
    }
}

/// Authorization Code + PKCE, so no client secret ships in the app.
public actor SpotifyAuth {
    public static let scopes = [
        "playlist-read-private", "playlist-read-collaborative",
        "user-top-read", "user-library-read",
        "user-read-playback-state", "user-modify-playback-state",
        "playlist-modify-private", "playlist-modify-public",
    ]

    struct Tokens: Codable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
        /// Space-separated scopes Spotify granted (missing for logins from older versions).
        var scope: String?
    }

    /// Whether the login allows a scope. Logins from before MoodMix asked for it don't.
    public func hasScope(_ scope: String) -> Bool {
        tokens?.scope?.split(separator: " ").contains { $0 == scope } ?? false
    }

    private let clientID: String
    private var tokens: Tokens?

    public init(clientID: String) {
        self.clientID = clientID
        if let json = Keychain.get("spotify.tokens"), let data = json.data(using: .utf8) {
            tokens = try? JSONDecoder().decode(Tokens.self, from: data)
        }
    }

    public var isLoggedIn: Bool { tokens != nil }

    public func logIn(using provider: AuthCodeProvider) async throws {
        guard !clientID.isEmpty else { throw SpotifyError.missingClientID }
        let verifier = Self.randomString(length: 64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded()
        let state = Self.randomString(length: 16)

        var c = URLComponents(string: "https://accounts.spotify.com/authorize")!
        c.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: provider.redirectURI.absoluteString),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "scope", value: Self.scopes.joined(separator: " ")),
            .init(name: "state", value: state),
        ]
        let callback = try await provider.authorize(url: c.url!)
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let error = items.first(where: { $0.name == "error" })?.value { throw SpotifyError.authFailed(error) }
        guard items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value else {
            throw SpotifyError.authFailed("unexpected redirect")
        }
        try await requestTokens([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": provider.redirectURI.absoluteString,
            "client_id": clientID,
            "code_verifier": verifier,
        ])
    }

    public func logOut() {
        tokens = nil
        Keychain.set(nil, for: "spotify.tokens")
    }

    /// A valid access token, refreshed if it is about to expire.
    public func accessToken() async throws -> String {
        guard let t = tokens else { throw SpotifyError.notLoggedIn }
        if t.expiresAt > Date().addingTimeInterval(60) { return t.accessToken }
        try await requestTokens(["grant_type": "refresh_token", "refresh_token": t.refreshToken, "client_id": clientID])
        return tokens!.accessToken
    }

    private func requestTokens(_ form: [String: String]) async throws {
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = form.map { "\($0.key)=\($0.value.formEncoded)" }.joined(separator: "&").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            if form["grant_type"] == "refresh_token" { logOut() }
            throw SpotifyError.authFailed(String(decoding: data, as: UTF8.self))
        }
        struct Response: Decodable { let access_token: String; let refresh_token: String?; let expires_in: Double; let scope: String? }
        let r = try JSONDecoder().decode(Response.self, from: data)
        let new = Tokens(accessToken: r.access_token,
                         refreshToken: r.refresh_token ?? tokens?.refreshToken ?? "",
                         expiresAt: Date().addingTimeInterval(r.expires_in),
                         scope: r.scope ?? tokens?.scope)
        tokens = new
        Keychain.set(String(decoding: try JSONEncoder().encode(new), as: UTF8.self), for: "spotify.tokens")
    }

    static func randomString(length: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<length).map { _ in chars.randomElement()! })
    }
}

extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension String {
    var formEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(.init(charactersIn: "-._~"))) ?? self
    }
}
