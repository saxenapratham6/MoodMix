#if os(macOS)
import AppKit
import MoodMixCore

/// Asks where to save, writes the CSV (for TuneMyMusic/Soundiiz) and JSON (everything MoodMix knows), and shows them in Finder.
@MainActor
enum Exporter {
    static func export(all: Bool, model: AppModel) async {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "Choose where to save your export"
        panel.prompt = "Export Here"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        let playlists = await model.exportPlaylists(all: all)
        guard !playlists.isEmpty else { return }
        let stamp = Date().formatted(.iso8601.year().month().day())
        let base = all ? "MoodMix playlists \(stamp)" : "\(playlists[0].name) \(stamp)"
            .replacingOccurrences(of: "/", with: "-")
        let csv = folder.appendingPathComponent(base + ".csv")
        let json = folder.appendingPathComponent(base + ".json")
        do {
            try PlaylistExport.csv(playlists).write(to: csv, atomically: true, encoding: .utf8)
            try PlaylistExport.json(playlists).write(to: json)
            NSWorkspace.shared.activateFileViewerSelecting([csv, json])
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

#endif
