import MoodMixCore
import SwiftUI
import UIKit

// The same palette as the Mac app (Sources/MoodMixMac/Theme.swift).
enum Theme {
    static let green = Color(red: 0.118, green: 0.843, blue: 0.376) // #1ED760
    static let elevated = Color(white: 0.11)
    static let subtext = Color(white: 0.70)
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

extension View {
    /// Liquid Glass on iOS 26, frosted material before that.
    @ViewBuilder
    func liquidGlass<S: Shape>(tint: Color? = nil, interactive: Bool = false, in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(Self.glass(tint: tint, interactive: interactive), in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }

    @available(iOS 26.0, *)
    private static func glass(tint: Color?, interactive: Bool) -> Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }
}

/// Album covers cached in memory at display size, so lists scroll smoothly.
@MainActor
final class ArtworkCache {
    static let shared = ArtworkCache()
    private let images = NSCache<NSURL, UIImage>()
    private var loading: [URL: Task<UIImage?, Never>] = [:]

    func cached(_ url: URL) -> UIImage? { images.object(forKey: url as NSURL) }

    func load(_ url: URL) async -> UIImage? {
        if let image = cached(url) { return image }
        if let task = loading[url] { return await task.value }
        let task = Task.detached(priority: .utility) { () -> UIImage? in
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
            return await UIImage(data: data)?.byPreparingThumbnail(ofSize: CGSize(width: 300, height: 300))
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
    var radius: CGFloat = 6
    @State private var loaded: UIImage?

    var body: some View {
        let image = url.flatMap { ArtworkCache.shared.cached($0) } ?? loaded
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
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

struct MoodTag: View {
    let mood: Mood

    var body: some View {
        Text(mood.title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(mood.color.opacity(0.45), in: .capsule)
            .foregroundStyle(.white)
    }
}

func formatTime(_ ms: Int) -> String {
    let s = max(ms, 0) / 1000
    return String(format: "%d:%02d", s / 60, s % 60)
}
