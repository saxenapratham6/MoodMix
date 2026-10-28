#if os(macOS)
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

/// A vinyl record with the album cover as its center label. It spins (33⅓ rpm) while the song plays;
/// the light's sheen stays put while the record turns underneath it, like a real turntable.
struct VinylRecord: View {
    let artworkURL: URL?
    let spinning: Bool
    var size: CGFloat

    var body: some View {
        ZStack {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !spinning)) { context in
                disc.rotationEffect(.degrees(context.date.timeIntervalSinceReferenceDate * 200))  // 33⅓ rpm = 200°/s
            }
            // Fixed reflections across the grooves.
            Circle()
                .fill(AngularGradient(colors: [.clear, .white.opacity(0.16), .clear, .clear, .white.opacity(0.10), .clear, .clear],
                                      center: .center))
                .blendMode(.screen)
                .allowsHitTesting(false)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.45), radius: 6, y: 3)
    }

    private var disc: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Color(white: 0.18), Color(white: 0.05), Color(white: 0.02)],
                                         center: .center, startRadius: 0, endRadius: size / 2))
            // Grooves in the ring between the label and the rim.
            ForEach(0..<5, id: \.self) { i in
                Circle()
                    .stroke(.white.opacity(i.isMultiple(of: 2) ? 0.09 : 0.045), lineWidth: 0.6)
                    .padding(size * 0.04 + CGFloat(i) * size * 0.03)
            }
            label
                .frame(width: size * Self.labelRatio, height: size * Self.labelRatio)
                .clipShape(Circle())
                .overlay(Circle().stroke(.black.opacity(0.5), lineWidth: 0.8))
            Circle().fill(Color(white: 0.06)).frame(width: size * 0.05, height: size * 0.05)  // spindle hole
            Circle().stroke(.white.opacity(0.12), lineWidth: 0.8)  // rim
        }
    }

    /// How much of the record the album cover covers: big enough to clearly see the song.
    static let labelRatio: CGFloat = 0.62

    @ViewBuilder private var label: some View {
        if let artworkURL {
            Artwork(url: artworkURL, size: size * Self.labelRatio, radius: size * Self.labelRatio / 2)
        } else {
            ZStack {
                Theme.green
                Image(systemName: "waveform").font(.system(size: size * 0.16, weight: .bold)).foregroundStyle(.black)
            }
        }
    }
}

#endif
