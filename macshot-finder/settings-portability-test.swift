import Foundation

func L(_ text: String) -> String { text }

@main
struct ForkSettingsPortabilityTest {
    static func main() {
        for key in ["SUEnableAutomaticChecks", "SnapletSettingsAppearance", "SnapletFinderClipboardRetention"] {
            precondition(SettingsPortability.isPortable(key))
        }
        for key in ["SnapletPassword", "SnapletSettingsAppearanceToken", "SnapletBookmark", "NSWindowState", "Country", "randomUppercaseKey".uppercased()] {
            precondition(!SettingsPortability.isPortable(key))
        }
        precondition(!SettingsPortability.isPortable("SnapletUnknownFutureKey"))
        precondition(SettingsPortability.isPortable("betaUpdatesEnabled"))
        print("PASS: both Snaplet preferences export; secret, bookmark and system-key exclusions remain intact")
    }
}
