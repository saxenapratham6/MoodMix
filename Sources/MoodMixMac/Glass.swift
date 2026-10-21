import AppKit
import ImageIO
import SwiftUI

// Liquid Glass on macOS 26, with a frosted-material fallback on older systems.

extension View {
    @ViewBuilder
    func liquidGlass<S: Shape>(tint: Color? = nil, interactive: Bool = false, in shape: S) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(Self.glass(tint: tint, interactive: interactive), in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
                .background((tint ?? .black).opacity(0.45), in: shape)
                .overlay(shape.stroke(.white.opacity(0.1), lineWidth: 1))
        }
    }

    @available(macOS 26.0, *)
    private static func glass(tint: Color?, interactive: Bool) -> Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }

    /// Lets glass shapes with the same container morph into each other (bar ↔ card ↔ bubble).
    @ViewBuilder
    func glassID(_ id: String, in namespace: Namespace.ID) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffectID(id, in: namespace)
        } else {
            self
        }
    }
}

/// Groups glass shapes so they blend and morph together.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

/// Buttons squish slightly when pressed, like iOS.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}

/// Glass pill: solid white when selected (Spotify's filter chips), glass otherwise.
struct GlassPill: View {
    let title: String
    var symbol: String? = nil
    let selected: Bool
    var fill = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol) }
                Text(title).lineLimit(1)
            }
            .font(.callout.weight(.semibold))
            .frame(maxWidth: fill ? .infinity : nil)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(selected ? .black : .white)
            .background(selected ? Color.white : .clear, in: .capsule)
            .modifier(UnselectedGlass(selected: selected))
            .contentShape(.capsule)
        }
        .buttonStyle(.pressable)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: selected)
    }

    private struct UnselectedGlass: ViewModifier {
        let selected: Bool
        func body(content: Content) -> some View {
            if selected { content } else { content.liquidGlass(interactive: true, in: Capsule()) }
        }
    }
}

/// Lets a SwiftUI area drag the whole floating panel (and tells us when the drag ends or was just a click).
struct DragHandle: NSViewRepresentable {
    var onClick: (() -> Void)? = nil
    var onDragEnded: () -> Void

    func makeNSView(context: Context) -> HandleView {
        let view = HandleView()
        view.onClick = onClick
        view.onDragEnded = onDragEnded
        return view
    }

    func updateNSView(_ view: HandleView, context: Context) {
        view.onClick = onClick
        view.onDragEnded = onDragEnded
    }

    final class HandleView: NSView {
        var onClick: (() -> Void)?
        var onDragEnded: (() -> Void)?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            let start = NSEvent.mouseLocation
            let origin = window.frame.origin
            var dragging = false
            while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
                if next.type == .leftMouseUp { break }
                let now = NSEvent.mouseLocation
                let dx = now.x - start.x, dy = now.y - start.y
                if !dragging && hypot(dx, dy) < 3 { continue }
                if !dragging {
                    dragging = true
                    NSCursor.closedHand.push()
                }
                window.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy))
            }
            if dragging {
                NSCursor.pop()
                onDragEnded?()
            } else {
                onClick?()
            }
        }
    }
}

/// The current song's album-art color, used to tint the glass like Spotify's player.
@MainActor @Observable
final class ArtworkPalette {
    private(set) var accent: Color?
    @ObservationIgnored private var cache: [URL: NSColor] = [:]
    @ObservationIgnored private var current: URL?

    func update(for url: URL?) async {
        guard url != current else { return }
        current = url
        guard let url else {
            withAnimation(.easeInOut(duration: 0.6)) { accent = nil }
            return
        }
        if cache[url] == nil,
           let (data, _) = try? await URLSession.shared.data(from: url),
           let color = Self.averageColor(of: data) {
            cache[url] = color
        }
        guard current == url, let color = cache[url] else { return }
        withAnimation(.easeInOut(duration: 0.6)) { accent = Color(nsColor: color) }
    }

    nonisolated static func averageColor(of data: Data) -> NSColor? {
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 24] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return nil }
        let average = NSColor(srgbRed: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255, blue: CGFloat(pixel[2]) / 255, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        average.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        // Richer and a little darker than the raw average, so white text stays readable.
        return NSColor(hue: h, saturation: min(1, s * 1.3 + 0.1), brightness: min(max(b, 0.35), 0.6), alpha: 1)
    }
}
