import AuthenticationServices
import MoodMixCore
import UIKit

/// Spotify login in the system sign-in sheet. Add `moodmix://callback` as a Redirect URI in your Spotify app.
final class WebAuthProvider: NSObject, AuthCodeProvider, ASWebAuthenticationPresentationContextProviding, @unchecked Sendable {
    let redirectURI = URL(string: "moodmix://callback")!
    private var session: ASWebAuthenticationSession?

    func authorize(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "moodmix") { callback, error in
                    if let callback {
                        continuation.resume(returning: callback)
                    } else {
                        continuation.resume(throwing: error ?? URLError(.cancelled))
                    }
                }
                session.presentationContextProvider = self
                self.session = session
                session.start()
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
