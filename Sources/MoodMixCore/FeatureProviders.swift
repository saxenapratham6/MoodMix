import Foundation

/// Measured audio features from ReccoBeats (free, no key), looked up by Spotify track ID.
public struct ReccoBeatsClient: Sendable {
    public init() {}

    /// Returns features for whichever IDs ReccoBeats knows; unknown IDs are simply absent.
    public func features(for ids: [String]) async -> [String: AudioFeatures] {
        var result: [String: AudioFeatures] = [:]
        for chunk in ids.chunked(into: 40) {
            var c = URLComponents(string: "https://api.reccobeats.com/v1/audio-features")!
            c.queryItems = [URLQueryItem(name: "ids", value: chunk.joined(separator: ","))]
            guard let data = try? await fetch(c.url!) else { continue }
            struct R: Decodable {
                struct F: Decodable {
                    let href: String?
                    let energy, valence, danceability, acousticness, instrumentalness, tempo: Double
                    let key, mode: Int
                }
                let content: [F]
            }
            guard let r = try? JSONDecoder().decode(R.self, from: data) else { continue }
            for f in r.content {
                guard let id = f.href?.split(separator: "/").last.map(String.init) else { continue }
                result[id] = AudioFeatures(energy: f.energy, valence: f.valence, danceability: f.danceability,
                                           acousticness: f.acousticness, instrumentalness: f.instrumentalness,
                                           tempo: f.tempo, key: f.key, mode: f.mode)
            }
        }
        return result
    }

    private func fetch(_ url: URL, attempt: Int = 0) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 429 && attempt < 3 {
            try await Task.sleep(for: .seconds(2 << attempt))
            return try await fetch(url, attempt: attempt + 1)
        }
        guard status == 200 else { throw URLError(.badServerResponse) }
        return data
    }
}

/// Mood labels (and feature estimates where measured data is missing) from Claude.
public struct ClaudeTagger: Sendable {
    public static let defaultModel = "claude-opus-5-5"

    let apiKey: String
    let model: String

    public init(apiKey: String, model: String = ClaudeTagger.defaultModel) {
        self.apiKey = apiKey
        self.model = model.isEmpty ? Self.defaultModel : model
    }

    public struct Tag: Decodable, Sendable {
        public let id: String
        public let moods: [Mood]
        public let genre: String
        public let energy: Double
        public let valence: Double
        public let tempo: Double
        public let key: Int
        public let mode: Int
    }

    public enum TaggerError: LocalizedError {
        case http(Int, String)
        case refused
        case badOutput

        public var errorDescription: String? {
            switch self {
            case .http(let code, let body): "Claude API returned \(code): \(body.prefix(200))"
            case .refused: "Claude declined to tag this batch."
            case .badOutput: "Claude returned output MoodMix could not read."
            }
        }
    }

    /// Tags up to ~100 tracks in one request.
    public func tag(_ tracks: [Track]) async throws -> [Tag] {
        let list = tracks.map { "\($0.id) | \($0.name) — \($0.artistLine) (\($0.album))" }.joined(separator: "\n")
        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "required": ["tracks"],
            "properties": [
                "tracks": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "required": ["id", "moods", "genre", "energy", "valence", "tempo", "key", "mode"],
                        "properties": [
                            "id": ["type": "string"],
                            "moods": ["type": "array", "items": ["type": "string", "enum": Mood.allCases.map(\.rawValue)]],
                            "genre": ["type": "string"],
                            "energy": ["type": "number"],
                            "valence": ["type": "number"],
                            "tempo": ["type": "number"],
                            "key": ["type": "integer"],
                            "mode": ["type": "integer"],
                        ],
                    ],
                ],
            ],
        ]
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "fallbacks": "default",
            "output_config": ["effort": "low", "format": ["type": "json_schema", "schema": schema]],
            "system": """
            You label songs for a mood-based music player. For each track, use what you know about the song \
            (or, if you don't know it, the artist's typical sound) to return:
            - moods: 1-3 of the allowed moods, strongest first
            - genre: a short genre name
            - energy and valence: 0 to 1, on Spotify's audio-feature scales
            - tempo: BPM; key: pitch class 0-11 (C=0), or -1 if unsure; mode: 1 major, 0 minor
            Return every track, using the exact id given.
            """,
            "messages": [["role": "user", "content": "Tracks (id | title — artists (album)):\n\(list)"]],
        ]

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 300
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw TaggerError.http(status, String(decoding: data, as: UTF8.self)) }

        struct Message: Decodable {
            struct Block: Decodable { let type: String; let text: String? }
            let content: [Block]
            let stop_reason: String?
        }
        let message = try JSONDecoder().decode(Message.self, from: data)
        if message.stop_reason == "refusal" { throw TaggerError.refused }
        guard let text = message.content.last(where: { $0.type == "text" })?.text else { throw TaggerError.badOutput }
        struct Output: Decodable { let tracks: [Tag] }
        do {
            return try JSONDecoder().decode(Output.self, from: Data(text.utf8)).tracks
        } catch {
            throw TaggerError.badOutput
        }
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
