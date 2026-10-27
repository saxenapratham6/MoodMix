import MoodMixCore
import ImageIO
import SwiftUI

enum Theme {
    static let background = Color.black
    static let panel = Color(white: 0.071)        // #121212
    static let elevated = Color(white: 0.11)
    static let hover = Color(white: 0.16)
    static let chip = Color(white: 0.16)
    static let subtext = Color(white: 0.70)
    static let green = Color(red: 0.118, green: 0.843, blue: 0.376) // #1ED760
}

extension Mood {
    var color: Color {
        switch self {
        case .chill: Color(red: 0.16, green: 0.55, blue: 0.60)
        case .happy: Color(red: 0.85, green: 0.65, blue: 0.10)
        case .energetic: Color(red: 0.90, green: 0.40, blue: 0.10)
        case .focus: Color(red: 0.30, green: 0.30, blue: 0.75)
        case .sad: Color(red: 0.18, green: 0.30, blue: 0.55)
        case .romantic: Color(red: 0.80, green: 0.25, blue: 0.45)
        case .party: Color(red: 0.55, green: 0.20, blue: 0.75)
        case .workout: Color(red: 0.80, green: 0.15, blue: 0.15)
        }
    }
}

/// Album covers, downloaded once and shrunk to display size, so scrolling lists don't refetch them.
@MainActor
final class ArtworkCache {
    static let shared = ArtworkCache()
    private let images = NSCache<NSURL, NSImage>()
    private var loading: [URL: Task<NSImage?, Never>] = [:]

    private init() { images.countLimit = 800 }

    func cached(_ url: URL) -> NSImage? { images.object(forKey: url as NSURL) }

    func load(_ url: URL) async -> NSImage? {
        if let image = cached(url) { return image }
        if let task = loading[url] { return await task.value }
        let task = Task.detached(priority: .utility) { () -> NSImage? in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: 300,
                  ] as CFDictionary) else { return nil }
            return NSImage(cgImage: thumb, size: .zero)
        }
        loading[url] = task
        let image = await task.value
        loading[url] = nil
        if let image { images.setObject(image, forKey: url as NSURL) }
        return image
    }
}

struct Artwork: View {
    let url: URL?
    var size: CGFloat
    var radius: CGFloat = 4
    @State private var loaded: NSImage?

    var body: some View {
        // Read the cache synchronously so rows scrolling back into view show their cover immediately.
        let image = url.flatMap { ArtworkCache.shared.cached($0) } ?? loaded
        ZStack {
            if let image {
                Image(nsImage: image).resizable().interpolation(.medium).scaledToFill()
            } else {
                Theme.elevated
                Image(systemName: "music.note").foregroundStyle(Theme.subtext)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: radius))
        .task(id: url) {
            guard let url else { loaded = nil; return }
            loaded = await ArtworkCache.shared.load(url)
        }
    }
}

/// Spotify-style pill: white when selected, dark grey otherwise.
struct Pill: View {
    let title: String
    var symbol: String? = nil
    let selected: Bool
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol) }
                Text(title).lineLimit(1)
            }
            .font(compact ? .caption.weight(.medium) : .callout.weight(.medium))
            .frame(maxWidth: compact ? .infinity : nil)
            .padding(.horizontal, compact ? 10 : 14)
            .padding(.vertical, compact ? 6 : 7)
            .foregroundStyle(selected ? .black : .white)
            .background(selected ? Color.white : Theme.chip, in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

struct MoodTag: View {
    let mood: Mood

    var body: some View {
        Text(mood.title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(mood.color.opacity(0.35), in: .capsule)
            .foregroundStyle(.white)
    }
}

func formatTime(_ ms: Int) -> String {
    let s = max(ms, 0) / 1000
    return String(format: "%d:%02d", s / 60, s % 60)
}
