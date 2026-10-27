import SwiftUI
import WidgetKit

// Widgets are shortcuts: each tap opens MoodMix with `moodmix://generate?mood=…` and starts that mix.
// (They don't show live playback: that would need the app running in the background, which iOS doesn't allow here.)

private enum WidgetMood: String, CaseIterable, Identifiable {
    case chill, happy, energetic, focus, sad, romantic, party, workout
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var url: URL { URL(string: "moodmix://generate?mood=\(rawValue)")! }

    var symbol: String {
        switch self {
        case .chill: "cloud.sun"
        case .happy: "sun.max"
        case .energetic: "bolt"
        case .focus: "brain.head.profile"
        case .sad: "cloud.rain"
        case .romantic: "heart"
        case .party: "party.popper"
        case .workout: "figure.run"
        }
    }

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

private let autoURL = URL(string: "moodmix://generate?mood=auto")!
private let green = Color(red: 0.118, green: 0.843, blue: 0.376)

private struct StaticEntry: TimelineEntry { let date = Date() }

private struct StaticProvider: TimelineProvider {
    func placeholder(in context: Context) -> StaticEntry { StaticEntry() }
    func getSnapshot(in context: Context, completion: @escaping (StaticEntry) -> Void) { completion(StaticEntry()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<StaticEntry>) -> Void) {
        completion(Timeline(entries: [StaticEntry()], policy: .never))
    }
}

// MARK: Home Screen: mood grid

private struct MoodGridView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let moods = family == .systemSmall ? Array(WidgetMood.allCases.prefix(4)) : WidgetMood.allCases
        VStack(alignment: .leading, spacing: 8) {
            Link(destination: autoURL) {
                HStack(spacing: 6) {
                    Image(systemName: "waveform").foregroundStyle(green)
                    Text("MoodMix").font(.caption.weight(.heavy))
                    Spacer()
                    Label("Auto", systemImage: "sparkles").font(.caption2.weight(.bold)).foregroundStyle(green)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: family == .systemSmall ? 2 : 4), spacing: 6) {
                ForEach(moods) { mood in
                    Link(destination: mood.url) {
                        VStack(spacing: 3) {
                            Image(systemName: mood.symbol).font(.system(size: 14, weight: .semibold))
                            Text(mood.title).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(mood.color.opacity(0.55), in: .rect(cornerRadius: 10))
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .containerBackground(for: .widget) { Color.black }
    }
}

struct MoodGridWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MoodGrid", provider: StaticProvider()) { _ in MoodGridView() }
            .configurationDisplayName("Moods")
            .description("Tap a mood to start a mix from your playlist.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: Lock Screen

private struct LockScreenView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "waveform").font(.title3.weight(.bold))
            }
            .widgetURL(autoURL)
        case .accessoryInline:
            Label("MoodMix · auto mix", systemImage: "waveform").widgetURL(autoURL)
        default:
            VStack(alignment: .leading, spacing: 2) {
                Label("MoodMix", systemImage: "waveform").font(.headline)
                Text("Tap for a mix that fits right now").font(.caption)
            }
            .widgetURL(autoURL)
        }
    }
}

struct LockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MoodMixLock", provider: StaticProvider()) { _ in
            LockScreenView().containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Auto mix")
        .description("Start a mix picked for the moment.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct MoodMixWidgets: WidgetBundle {
    var body: some Widget {
        MoodGridWidget()
        LockScreenWidget()
    }
}
