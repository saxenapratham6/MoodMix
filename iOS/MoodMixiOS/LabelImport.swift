import MoodMixCore
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// "MoodMix labels.moodmixlabels", exported from the Mac app's Settings.
    static let moodMixLabels = UTType(exportedAs: "com.saxenapratham.moodmix.labels", conformingTo: .data)
}

/// Brings in the Mac's mood labels so the iPhone doesn't pay Claude to label the same songs again.
@MainActor @Observable
final class LabelImport {
    static let shared = LabelImport()
    private(set) var message: String?

    func importFile(at url: URL, into model: AppModel) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            message = "Couldn't read that file."
            return
        }
        let added = await model.importLabels(data)
        message = added > 0 ? "Imported labels for \(added) songs from your Mac." : "Those songs already had labels."
    }

    func dismiss() { message = nil }
}

/// Shown on the Now tab when songs are waiting to be labeled: import from the Mac for free, or let Claude do it.
struct LabelPrompt: View {
    @Environment(AppModel.self) private var model
    @State private var importing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("\(model.unlabeledCount) songs need mood labels", systemImage: "tag.fill")
                .font(.subheadline.weight(.bold))
            Text("Import them from MoodMix on your Mac for free (Settings → Export labels for iPhone, then AirDrop the file here), or let Claude label them with your Anthropic key.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
            HStack(spacing: 8) {
                Button { importing = true } label: {
                    Label("Import from Mac", systemImage: "square.and.arrow.down")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .foregroundStyle(.black)
                        .background(Theme.green, in: .capsule)
                }
                Button { Task { await model.approveLabeling() } } label: {
                    Label("Label with Claude", systemImage: "sparkles")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .liquidGlass(interactive: true, in: Capsule())
                }
                .disabled(model.anthropicKey.isEmpty)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(tint: Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 18))
        .fileImporter(isPresented: $importing, allowedContentTypes: [.moodMixLabels, .data]) { result in
            guard case .success(let url) = result else { return }
            Task { await LabelImport.shared.importFile(at: url, into: model) }
        }
    }
}
