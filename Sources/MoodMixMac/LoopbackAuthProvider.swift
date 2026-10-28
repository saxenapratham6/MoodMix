#if os(macOS)
import AppKit
import MoodMixCore
import Network

/// Opens Spotify's login page in the browser and catches the redirect on 127.0.0.1:8888.
/// Register `http://127.0.0.1:8888/callback` as a Redirect URI in your Spotify app.
final class LoopbackAuthProvider: AuthCodeProvider, @unchecked Sendable {
    static let port: NWEndpoint.Port = 8888
    let redirectURI = URL(string: "http://127.0.0.1:8888/callback")!

    func authorize(url: URL) async throws -> URL {
        let listener = try NWListener(using: .tcp, on: Self.port)
        defer { listener.cancel() }

        return try await withCheckedThrowingContinuation { continuation in
            var finished = false
            func finish(_ result: Result<URL, Error>) {
                guard !finished else { return }
                finished = true
                continuation.resume(with: result)
            }

            listener.newConnectionHandler = { connection in
                connection.start(queue: .main)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, _ in
                    let request = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
                    // "GET /callback?code=…&state=… HTTP/1.1"
                    let path = request.split(separator: " ").dropFirst().first.map(String.init) ?? ""
                    let isCallback = path.hasPrefix("/callback")
                    let html = isCallback
                        ? "<h2 style='font-family:-apple-system'>You're logged in. You can close this tab and go back to MoodMix.</h2>"
                        : "Not found"
                    let response = "HTTP/1.1 \(isCallback ? "200 OK" : "404 Not Found")\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
                    connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
                    if isCallback, let callback = URL(string: "http://127.0.0.1:8888" + path) {
                        finish(.success(callback))
                    }
                }
            }
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready: NSWorkspace.shared.open(url)
                case .failed(let error): finish(.failure(error))
                default: break
                }
            }
            listener.start(queue: .main)
        }
    }
}

#endif
