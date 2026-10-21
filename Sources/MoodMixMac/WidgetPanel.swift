import AppKit
import MoodMixCore
import SwiftUI

/// A borderless panel that floats above other windows (and full-screen apps) without stealing focus.
final class WidgetPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the floating widget and keeps it pinned to the bottom center of the screen, above the Dock.
@MainActor
final class WidgetController {
    static let collapsedSize = NSSize(width: 600, height: 92)
    static let expandedSize = NSSize(width: 600, height: 680)

    let panel: WidgetPanel
    private var expanded = false

    init(model: AppModel) {
        panel = WidgetPanel(contentRect: NSRect(origin: .zero, size: Self.collapsedSize),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false  // SwiftUI draws its own soft shadow
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        // The window's size is set only by `place`. The SwiftUI view just fills a plain container with an
        // autoresizing mask, so SwiftUI and the window never negotiate size through Auto Layout. That
        // negotiation is what looped forever and crashed while the content changed during a resize.
        let host = NSHostingView(rootView: WidgetView(controller: self).environment(model))
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = true
        host.autoresizingMask = [.width, .height]
        let container = NSView(frame: NSRect(origin: .zero, size: Self.collapsedSize))
        host.frame = container.bounds
        container.addSubview(host)
        panel.contentView = container
        place(size: Self.collapsedSize, animate: false)
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.place(size: self?.panel.frame.size ?? Self.collapsedSize, animate: false) }
        }
    }

    var isVisible: Bool { panel.isVisible }

    func show() { panel.orderFrontRegardless() }
    func hide() { panel.orderOut(nil) }
    func toggleVisible() { isVisible ? hide() : show() }

    func resize(expanded: Bool) {
        self.expanded = expanded
        place(size: expanded ? Self.expandedSize : Self.collapsedSize, animate: true)
    }

    private func place(size: NSSize, animate: Bool) {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let frame = NSRect(x: visible.midX - size.width / 2, y: visible.minY + 4, width: size.width, height: size.height)
        // SwiftUI animates the card itself, so the window can snap to its new size.
        guard panel.frame != frame else { return }
        panel.setFrame(frame, display: true, animate: false)
    }
}
