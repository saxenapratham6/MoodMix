import AppKit
import MoodMixCore
import SwiftUI

/// The menu bar dropdown, styled like macOS's Now Playing panel: what's playing, quick moods, Generate.
struct MenuBarPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let accent = Shared.palette.accent ?? model.mood.color
        VStack(alignment: .leading, spacing: 14) {
            nowPlaying(accent)

            GlassGroup(spacing: 6) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(Mood.allCases) { mood in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                model.autoMood = false
                                model.journeyMode = false
                                model.mood = mood
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: mood.symbol).font(.system(size: 15, weight: .semibold))
                                Text(mood.title).font(.caption2.weight(.semibold)).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .foregroundStyle(model.mood == mood ? .black : .white)
                            .background(model.mood == mood ? Color.white : .clear, in: .rect(cornerRadius: 12, style: .continuous))
                            .modifier(TileGlass(selected: model.mood == mood))
                            .contentShape(.rect)
                        }
                        .buttonStyle(.pressable)
                    }
                }
            }

            HStack(spacing: 8) {
                GenerateButton()
                Button { Task { await model.matchCurrentSong() } } label: {
                    Label("Match", systemImage: "dot.radiowaves.left.and.right")
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .liquidGlass(interactive: true, in: Capsule())
                }
                .buttonStyle(.pressable)
                .disabled(model.nowPlaying == nil)
            }

            if model.autoMood, let suggestion = model.suggestion {
                Label("Auto: \(suggestion.mood.title) · \(suggestion.reason)", systemImage: "sparkles")
                    .font(.caption).foregroundStyle(.white.opacity(0.75))
            }
            if let sleep = model.sleepTimerText {
                Label(sleep, systemImage: "moon.zzz.fill").font(.caption).foregroundStyle(Theme.green)
            }
            if let status = model.statusLine {
                Text(status).font(.caption).foregroundStyle(.white.opacity(0.7)).lineLimit(2)
            }

            Divider().overlay(.white.opacity(0.15))

            VStack(spacing: 2) {
                MenuRow(title: Shared.widget?.isVisible == false ? "Show Widget" : "Hide Widget", symbol: "rectangle.bottomthird.inset.filled") {
                    Shared.widget?.toggleVisible()
                }
                MenuRow(title: "Shrink to Bubble", symbol: "circle.dashed") { Shared.widget?.shrinkToBubble() }
                MenuRow(title: "Reset Widget Position", symbol: "arrow.down.to.line") {
                    Shared.widget?.show()
                    Shared.widget?.resetPosition()
                }
                MenuRow(title: "Open Spotify", symbol: "music.note") { SpotifyLauncher.bringToFront() }
                SettingsLink {
                    MenuRowLabel(title: "Settings…", symbol: "gearshape")
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true) })
                MenuRow(title: "Quit MoodMix", symbol: "power") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 320)
        .background(alignment: .top) {
            LinearGradient(colors: [accent.opacity(0.55), .clear], startPoint: .top, endPoint: .center)
                .allowsHitTesting(false)
        }
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
        .task(id: model.nowPlaying?.track.artworkURL) {
            await Shared.palette.update(for: model.nowPlaying?.track.artworkURL)
        }
    }

    @ViewBuilder private func nowPlaying(_ accent: Color) -> some View {
        HStack(spacing: 12) {
            if let np = model.nowPlaying {
                Artwork(url: np.track.artworkURL, size: 64, radius: 10)
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                VStack(alignment: .leading, spacing: 3) {
                    Text(np.track.name).font(.headline).lineLimit(1)
                    Text(np.track.artistLine).font(.caption).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                    HStack(spacing: 4) {
                        ForEach(model.profiles[np.track.id]?.moods.prefix(2) ?? [], id: \.self) { MoodTag(mood: $0) }
                    }
                }
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 64, height: 64)
                    .background(Theme.green, in: .rect(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text("MoodMix").font(.headline)
                    Text("Nothing playing").font(.caption).foregroundStyle(.white.opacity(0.7))
                }
            }
            Spacer(minLength: 0)
        }
        .overlay(alignment: .bottomTrailing) { Transport(size: .regular).scaleEffect(0.9, anchor: .bottomTrailing) }
        .padding(10)
        .liquidGlass(tint: accent.opacity(0.35), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private struct TileGlass: ViewModifier {
        let selected: Bool
        func body(content: Content) -> some View {
            if selected { content } else { content.liquidGlass(interactive: true, in: RoundedRectangle(cornerRadius: 12, style: .continuous)) }
        }
    }
}

private struct MenuRow: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) { MenuRowLabel(title: title, symbol: symbol) }
            .buttonStyle(.plain)
    }
}

private struct MenuRowLabel: View {
    let title: String
    let symbol: String
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).frame(width: 18).foregroundStyle(.white.opacity(0.75))
            Text(title)
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(hovering ? Color.white.opacity(0.12) : .clear, in: .rect(cornerRadius: 7))
        .contentShape(.rect)
        .onHover { hovering = $0 }
    }
}
