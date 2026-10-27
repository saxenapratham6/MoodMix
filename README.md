# MoodMix

A floating Spotify widget for Premium users. Pick a mood and MoodMix builds a queue **only from your own playlist** (no suggested tracks), leaning on your favorites. It orders the songs so each one flows into the next, then plays them on your Spotify.

On macOS it's a Liquid Glass widget (no window, no Dock icon), tinted with the current album art:

- **Bar:** now playing, ⏮ ⏯ ⏭, **Generate**, and a chevron that grows the control card out of the bar: playlists, moods, energy shape, length, favorites weight, **Generate** / **Match** (queue songs that fit what's playing now) / **Analyze**, and Up next.
- **Move it anywhere:** drag the bar or card. Drag it to the left or right screen edge (or click ◌) and it becomes a **bubble** with the album art and a progress ring; click the bubble to bring the bar back.
- **Queue:** the card's Queue tab shows now playing and what's next. Drag to reorder, remove songs, double-click to jump, or search the playlist to add any song *next* or *at the end*. A song from another mood plays where you put it, then the queue carries on in its mood, topping itself up when it runs low. MoodMix plays the queue from a private **MoodMix Queue** playlist in your library (Spotify's desktop app can drop plain lists of songs); songs added at the end just append to it, while reorders rewrite it and resume the current song where it was (expect a brief blip).
- **Bubble:** a spinning vinyl record with the album cover as its label and a progress ring; hover it for ⏮ ⏯ ⏭ underneath, click it to reopen the bar.
- **Menu bar:** a Now Playing–style glass panel with quick moods, Generate, Match, show/hide, bubble, reset position, Settings and Quit.
- It launches Spotify in the background if it isn't open.

macOS first. The core (`MoodMixCore`) is platform-neutral, so the iOS app can reuse it.

## How it works

1. **Load:** reads your playlist through the official Spotify Web API (`/playlists/{id}/items`).
2. **Favorites:** scores each song from your top tracks (4 weeks, 6 months and all time) and your Liked Songs.
3. **Analyze (cached once per song):**
   - Measured audio data (energy, valence, tempo, key) comes from [ReccoBeats](https://reccobeats.com), because Spotify closed its audio-features API to new apps in 2024.
   - Claude labels every song's moods and estimates audio data for any song ReccoBeats doesn't know.
4. **Pick:** keeps songs that fit the mood, ranked by mood fit and favorites (you set the balance), with a little randomness so each remix is different.
5. **Order (the "mixing"):** each next song is chosen by
   - harmonic compatibility on the Camelot wheel (same key, ±1, or relative major/minor),
   - tempo closeness (half and double time count as a match),
   - your energy arc: steady, build up, wind down, or peak in the middle,
   - and two songs by the same artist never play back-to-back.
6. **Play:** starts playback of exactly that list, with shuffle off, on your active Spotify device.

Spotify doesn't let other apps process its audio, so the actual crossfade comes from Spotify itself. Turn on **Settings → Playback → Crossfade (6–8 s)** or **Automix**. MoodMix's ordering is what makes those fades sound good.

## Setup

1. Go to https://developer.spotify.com/dashboard, click **Create app** and choose **Web API**.
   - Redirect URI: `http://127.0.0.1:8888/callback`
   - In Dev Mode, the app owner needs Premium.
2. Get an Anthropic API key from https://console.anthropic.com.
3. Build and run:
   ```bash
   swift run MoodMix
   ```
4. From the MoodMix menu bar icon → **Settings…**, paste your Spotify Client ID and Anthropic key.
5. Expand the widget, log in, pick your playlist (moods are labeled automatically, and new songs you add in Spotify are picked up within a minute), choose a mood and press **Generate**.

Keep the Spotify app open on some device (Mac or phone) so there's somewhere to play.

## Everything else it does

- **Learns from you:** skip a song within 30 s and it fits that mood a little less; listen through and it fits a little more. Right-click any song → *This song is more…* to set its mood yourself.
- **Auto mood:** picks the mood from the time of day, whether headphones are on, and what you usually choose around now.
- **Journeys:** a mix that moves through up to 4 moods in order (e.g. Sad → Chill → Happy), easing the energy between sections.
- **Sleep timer** (🌙): stop after this song, at the end of the mix, or fade out after 15–90 minutes.
- **Save as playlist:** save the queue to your Spotify library.
- **Insights:** songs per mood, moods that are thin, your most-played songs, and a duplicate cleaner.
- **Export:** CSV for TuneMyMusic / Soundiiz (to move to Apple Music or YouTube Music) and JSON with each song's moods, BPM and key.
- **Shortcuts (any app, also listed in the menu bar panel):** ⌃⌥G generate · ⌃⌥Space play/pause · ⌃⌥← → previous/next · ⌃⌥O card · ⌃⌥M widget · ⌃⌥B bubble · ⌃⌥1–8 mood mixes.

## iPhone app

`iOS/` holds the iPhone app (Now / Queue / Insights tabs, Liquid Glass on iOS 26) and its widgets: a Home Screen mood grid and Lock Screen buttons that start a mix.

- **Now** shows the song as a spinning vinyl record with the cover as its label (same as the Mac bubble); the app icon is a vinyl too (`scripts/make-icon.swift` draws it).
- If Spotify isn't running on the phone, Generate opens Spotify for a moment; tap **◀ MoodMix** in the top-left corner to come back and the mix starts. Mixes play on the phone unless another device is already playing.

1. In your Spotify app's dashboard, also add the Redirect URI `moodmix://callback`.
2. Open `iOS/MoodMixiOS.xcodeproj` in Xcode (regenerate it with `cd iOS && xcodegen generate` after changing `project.yml`).
3. Select the **MoodMixiOS** target → *Signing & Capabilities* → choose your Team (a free Apple ID works), do the same for **MoodMixWidgets**, then run on your iPhone.

There's no Dynamic Island / Live Activity: keeping it up to date while Spotify plays in the background would need a push server.

## Notes

- Songs added to a playlist more than once are counted once (the card notes how many duplicates were skipped).
- Spotify only returns playlist items for playlists you **own or collaborate on**. To use someone else's playlist, copy it to your own playlist first.
- Claude's default model is `claude-opus-5-5`. You can switch to `claude-haiku-5-5` in Settings for a much cheaper first pass over thousands of songs. Results are cached in `~/Library/Application Support/MoodMix/profiles.json`.
- Tokens and keys are stored in the macOS Keychain.

## Roadmap

- [ ] Live Activity on the iPhone (needs a small push server)
- [ ] Direct Apple Music import (needs an Apple Developer token)
