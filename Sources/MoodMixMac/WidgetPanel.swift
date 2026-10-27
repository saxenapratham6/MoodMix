import AppKit
import MoodMixCore
import SwiftUI

/// A borderless panel that floats above other windows (and full-screen apps) without stealing focus.
final class WidgetPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the floating widget: where it is, and whether it's a bar, an open card, or a bubble on a screen edge.
@MainActor @Observable
final class WidgetController {
    enum Mode: String { case bar, expanded, bubble }
    enum Side: String { case left, right }

    /// Room around the glass for its shadow.
    static let pad: CGFloat = 18
    static let barSize = NSSize(width: 580, height: 64)
    static let bubbleDiameter: CGFloat = 88
    static let gap: CGFloat = 10
    static let pillWidth: CGFloat = 112
    static let pillHeight: CGFloat = 44
    /// Gap between the record and the screen edge; leaves room to center the pill under it.
    static let bubbleInset: CGFloat = 20
    static let pillGap: CGFloat = 8

    private(set) var mode: Mode = .bar
    /// Drives the card's SwiftUI transition; lags `mode` so the card can animate out before the window shrinks.
    private(set) var showCard = false
    /// The card opens downward when the bar sits near the top of the screen.
    private(set) var cardBelow = false
    private(set) var bubbleSide: Side = .right
    /// The card's measured height; the window and the card's slide distance follow it.
    private(set) var cardHeight: CGFloat
    /// Hovering the record fades in a pill with playback controls. The window always has room for it,
    /// so nothing resizes (and the record never moves) when it comes and goes.
    private(set) var pillVisible = false
    /// The playback pill sits under the record, or above it when the record is near the bottom of the screen.
    private(set) var pillAbove = false

    @ObservationIgnored let panel: WidgetPanel
    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    @ObservationIgnored private var pointerTimer: Timer?
    @ObservationIgnored private var barOrigin: NSPoint?
    @ObservationIgnored private var bubbleCenterY: CGFloat
    @ObservationIgnored private let defaults = UserDefaults.standard

    init(model: AppModel) {
        let savedHeight = defaults.double(forKey: "widget.cardHeight")
        cardHeight = savedHeight > 0 ? savedHeight : 470
        let savedBubbleY = defaults.double(forKey: "widget.bubbleY")
        bubbleCenterY = savedBubbleY > 0 ? savedBubbleY : 400
        bubbleSide = Side(rawValue: defaults.string(forKey: "widget.bubbleSide") ?? "") ?? .right
        if defaults.object(forKey: "widget.barX") != nil {
            barOrigin = NSPoint(x: defaults.double(forKey: "widget.barX"), y: defaults.double(forKey: "widget.barY"))
        }
        mode = defaults.string(forKey: "widget.mode") == Mode.bubble.rawValue ? .bubble : .bar

        panel = WidgetPanel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 100),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false  // SwiftUI draws its own soft shadow
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        // The window's size is set only by `layout`. The SwiftUI view just fills a frame-based container,
        // so SwiftUI and the window never negotiate size through Auto Layout (that loop used to crash).
        let host = NSHostingView(rootView: WidgetView().environment(model).environment(self))
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = true
        host.autoresizingMask = [.width, .height]
        let container = NSView(frame: panel.contentRect(forFrameRect: panel.frame))
        host.frame = container.bounds
        container.addSubview(host)
        panel.contentView = container

        layout(animate: false)
        pointerTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.trackPointer() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout(animate: false) }
        }
    }

    var isVisible: Bool { panel.isVisible }
    func show() { panel.orderFrontRegardless() }
    func hide() { panel.orderOut(nil) }
    func toggleVisible() { isVisible ? hide() : show() }

    // MARK: Modes

    func toggleExpanded() { mode == .expanded ? collapse() : expand() }

    func expand() {
        show()
        resetBubbleHover()
        if mode == .bubble { restoreFromBubble() }
        mode = .expanded
        layout(animate: false)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { showCard = true }
    }

    func collapse(then next: (() -> Void)? = nil) {
        guard mode == .expanded else { next?(); return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            showCard = false
        } completion: {
            self.mode = .bar
            self.layout(animate: false)
            next?()
        }
    }

    func shrinkToBubble(side: Side? = nil, centerY: CGFloat? = nil) {
        show()
        collapse {
            let bar = self.barRect()
            self.bubbleSide = side ?? (bar.midX < self.visibleFrame.midX ? .left : .right)
            self.bubbleCenterY = centerY ?? bar.midY
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { self.mode = .bubble }
            self.layout(animate: true)
            self.save()
        }
    }

    func restoreFromBubble() {
        guard mode == .bubble else { return }
        resetBubbleHover()
        let visible = visibleFrame
        let x = bubbleSide == .left ? visible.minX + 12 : visible.maxX - Self.barSize.width - 12
        barOrigin = NSPoint(x: x, y: bubbleCenterY - Self.barSize.height / 2)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { mode = .bar }
        layout(animate: true)
        save()
    }

    /// Mouse entered or left the record (and its pill).
    func setBubbleHover(_ inside: Bool) {
        guard mode == .bubble else { return }
        if inside {
            hoverTask?.cancel()
            hoverTask = nil
            if !pillVisible { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { pillVisible = true } }
        } else if pillVisible, hoverTask == nil {
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.22)) { pillVisible = false }
                hoverTask = nil
            }
        }
    }

    private func resetBubbleHover() {
        hoverTask?.cancel()
        hoverTask = nil
        pillVisible = false
    }

    /// In bubble mode the window is bigger than the record, so follow the pointer ourselves: hover shows the
    /// pill, and the empty part of the window lets clicks through to whatever is underneath.
    private func trackPointer() {
        guard mode == .bubble else {
            if panel.ignoresMouseEvents { panel.ignoresMouseEvents = false }
            return
        }
        let mouse = NSEvent.mouseLocation
        let record = recordRect.insetBy(dx: -4, dy: -4)
        let zone = pillVisible ? record.union(pillRect).insetBy(dx: -6, dy: -6) : record
        let inside = zone.contains(mouse)
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
        setBubbleHover(inside)
    }

    /// Where the record and the pill are on screen, inside the bubble-mode window.
    private var recordRect: NSRect {
        let inner = panel.frame.insetBy(dx: Self.pad, dy: Self.pad)
        let d = Self.bubbleDiameter
        return NSRect(x: inner.midX - d / 2, y: pillAbove ? inner.minY : inner.maxY - d, width: d, height: d)
    }

    private var pillRect: NSRect {
        let inner = panel.frame.insetBy(dx: Self.pad, dy: Self.pad)
        return NSRect(x: inner.midX - Self.pillWidth / 2, y: pillAbove ? inner.maxY - Self.pillHeight : inner.minY,
                      width: Self.pillWidth, height: Self.pillHeight)
    }

    /// Puts the widget back at the bottom center.
    func resetPosition() {
        barOrigin = nil
        collapse {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { self.mode = .bar }
            self.layout(animate: true)
            self.save()
        }
    }

    /// Called by the drag handle when the user lets go: snap to an edge as a bubble, or stay put as a bar.
    func dragEnded() {
        let mouse = NSEvent.mouseLocation
        let visible = (NSScreen.screens.first { $0.frame.contains(mouse) } ?? panel.screen ?? NSScreen.main)?.visibleFrame ?? visibleFrame
        let inner = panel.frame.insetBy(dx: Self.pad, dy: Self.pad)

        switch mode {
        case .bubble:
            let bubble = recordRect
            resetBubbleHover()
            let nearLeft = bubble.midX - visible.minX < 140
            let nearRight = visible.maxX - bubble.midX < 140
            if nearLeft || nearRight {
                bubbleSide = nearLeft ? .left : .right
                bubbleCenterY = bubble.midY
            } else {
                // Pulled away from the edge: open back up into a bar right there.
                barOrigin = NSPoint(x: bubble.midX - Self.barSize.width / 2, y: bubble.midY - Self.barSize.height / 2)
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { mode = .bar }
            }
            layout(animate: true)
            save()

        case .bar, .expanded:
            let bar = barRectInPanel()
            barOrigin = bar.origin
            let edge: Side? =
                mouse.x - visible.minX < 48 || bar.minX < visible.minX - 4 ? .left :
                visible.maxX - mouse.x < 48 || bar.maxX > visible.maxX + 4 ? .right : nil
            if let edge {
                shrinkToBubble(side: edge, centerY: min(max(mouse.y, visible.minY + 40), visible.maxY - 40))
            } else {
                layout(animate: true)
                save()
            }
        }
    }

    /// The card reports its natural height so the window hugs it (no empty space).
    func cardHeightChanged(_ height: CGFloat) {
        guard height > 40, abs(height - cardHeight) > 0.5 else { return }
        cardHeight = height
        defaults.set(Double(height), forKey: "widget.cardHeight")
        if mode == .expanded { layout(animate: false) }
    }

    // MARK: Layout

    private var visibleFrame: NSRect { (panel.screen ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame }

    /// Where the bar should be, kept fully on screen.
    private func barRect() -> NSRect {
        let visible = visibleFrame
        let size = Self.barSize
        var origin = barOrigin ?? NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 6)
        origin.x = min(max(origin.x, visible.minX + 6), visible.maxX - size.width - 6)
        origin.y = min(max(origin.y, visible.minY + 6), visible.maxY - size.height - 6)
        return NSRect(origin: origin, size: size)
    }

    /// Where the bar currently is inside the (possibly just dragged) panel.
    private func barRectInPanel() -> NSRect {
        let inner = panel.frame.insetBy(dx: Self.pad, dy: Self.pad)
        let y = mode == .expanded && cardBelow ? inner.maxY - Self.barSize.height : inner.minY
        return NSRect(x: inner.minX, y: y, width: Self.barSize.width, height: Self.barSize.height)
    }

    private func targetFrame() -> NSRect {
        let visible = visibleFrame
        switch mode {
        case .bubble:
            let d = Self.bubbleDiameter
            let x = bubbleSide == .left ? visible.minX + Self.bubbleInset : visible.maxX - d - Self.bubbleInset
            let y = min(max(bubbleCenterY - d / 2, visible.minY + 8), visible.maxY - d - 8)
            var rect = NSRect(x: x, y: y, width: d, height: d)
            // Always leave room for the pill under the record (above it near the bottom of the screen),
            // centered, so hovering never resizes the window.
            let extraHeight = Self.pillHeight + Self.pillGap
            pillAbove = rect.minY - extraHeight < visible.minY + 8
            if !pillAbove { rect.origin.y -= extraHeight }
            rect.size.height += extraHeight
            if Self.pillWidth > d {
                rect.origin.x -= (Self.pillWidth - d) / 2
                rect.size.width = Self.pillWidth
            }
            return rect.insetBy(dx: -Self.pad, dy: -Self.pad)
        case .bar:
            return barRect().insetBy(dx: -Self.pad, dy: -Self.pad)
        case .expanded:
            let bar = barRect()
            let extra = Self.gap + cardHeight
            let roomAbove = visible.maxY - bar.maxY
            let roomBelow = bar.minY - visible.minY
            cardBelow = roomAbove < extra && roomBelow > roomAbove
            var frame = bar
            if cardBelow { frame.origin.y -= extra }
            frame.size.height += extra
            return frame.insetBy(dx: -Self.pad, dy: -Self.pad)
        }
    }

    private func layout(animate: Bool) {
        let frame = targetFrame()
        guard panel.frame != frame else { return }
        if animate {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.32
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private func save() {
        defaults.set(mode == .bubble ? Mode.bubble.rawValue : Mode.bar.rawValue, forKey: "widget.mode")
        defaults.set(bubbleSide.rawValue, forKey: "widget.bubbleSide")
        defaults.set(Double(bubbleCenterY), forKey: "widget.bubbleY")
        if let barOrigin {
            defaults.set(Double(barOrigin.x), forKey: "widget.barX")
            defaults.set(Double(barOrigin.y), forKey: "widget.barY")
        } else {
            defaults.removeObject(forKey: "widget.barX")
            defaults.removeObject(forKey: "widget.barY")
        }
    }
}
