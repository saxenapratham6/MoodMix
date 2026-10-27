import AppKit
import Carbon.HIToolbox
import MoodMixCore

/// System-wide shortcuts (⌃⌥ + key) that work from any app, without Accessibility permission.
@MainActor
final class HotKeys {
    static let shared = HotKeys()

    struct Shortcut: Identifiable {
        let id: UInt32
        let keyCode: Int
        let keys: String
        let title: String
        let action: @MainActor () -> Void
    }

    private(set) var shortcuts: [Shortcut] = []
    private var refs: [EventHotKeyRef] = []
    private var handlerInstalled = false

    func register(model: AppModel, widget: WidgetController) {
        let moodKeys = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8]
        var list: [Shortcut] = [
            Shortcut(id: 1, keyCode: kVK_ANSI_G, keys: "⌃⌥G", title: "Generate a mix") { Task { await model.generate() } },
            Shortcut(id: 2, keyCode: kVK_Space, keys: "⌃⌥Space", title: "Play / pause") { Task { await model.togglePlayPause() } },
            Shortcut(id: 3, keyCode: kVK_RightArrow, keys: "⌃⌥→", title: "Next song") { Task { await model.skipNext() } },
            Shortcut(id: 4, keyCode: kVK_LeftArrow, keys: "⌃⌥←", title: "Previous song") { Task { await model.skipPrevious() } },
            Shortcut(id: 5, keyCode: kVK_ANSI_O, keys: "⌃⌥O", title: "Open / close the widget card") { widget.toggleExpanded() },
            Shortcut(id: 6, keyCode: kVK_ANSI_M, keys: "⌃⌥M", title: "Show / hide the widget") { widget.toggleVisible() },
            Shortcut(id: 7, keyCode: kVK_ANSI_B, keys: "⌃⌥B", title: "Bubble / bar") {
                widget.mode == .bubble ? widget.restoreFromBubble() : widget.shrinkToBubble()
            },
        ]
        for (i, mood) in Mood.allCases.enumerated() where i < moodKeys.count {
            list.append(Shortcut(id: UInt32(10 + i), keyCode: moodKeys[i], keys: "⌃⌥\(i + 1)", title: "\(mood.title) mix") {
                model.autoMood = false
                model.journeyMode = false
                model.mood = mood
                Task { await model.generate() }
            })
        }
        shortcuts = list
        installHandler()
        for shortcut in list {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x4D4D_4958), id: shortcut.id)  // "MMIX"
            let status = RegisterEventHotKey(UInt32(shortcut.keyCode), UInt32(controlKey | optionKey), id,
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { refs.append(ref) }
        }
    }

    private func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKey = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKey)
            let id = hotKey.id
            DispatchQueue.main.async {
                MainActor.assumeIsolated { HotKeys.shared.shortcuts.first { $0.id == id }?.action() }
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
