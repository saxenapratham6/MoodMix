#if !os(macOS)
/// The menu bar widget is macOS-only. On other platforms this target builds to a stub, so opening the
/// package in Xcode with an iPhone selected doesn't fail; the iPhone app is iOS/MoodMixiOS.xcodeproj.
@main
enum MoodMixMacUnavailable {
    static func main() {
        print("MoodMix's widget runs on macOS. For the iPhone app, open iOS/MoodMixiOS.xcodeproj.")
    }
}
#endif
