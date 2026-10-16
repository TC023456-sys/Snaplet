"""Remove superseded fork plumbing from the pinned, patched upstream source.

Run after branding and settings redesign. Fail closed if upstream shapes change.
"""
import json
from pathlib import Path
import re
import sys

source = Path(sys.argv[1]).resolve()
app = source / 'macshot'


def replace_once(text, old, new=''):
    assert text.count(old) == 1, old
    return text.replace(old, new)


path = app / 'AppDelegate.swift'
text = path.read_text()
text = replace_once(text, '    private var pendingScreenCaptureURLs: [URL] = []\n')
text = replace_once(text, '''            // Closing onboarding abandons any action that was waiting for its
            // permission; never surprise the user by replaying it much later.
            self.pendingScreenCaptureURLs.removeAll()
''')
text = replace_once(text, '''        let urls = pendingScreenCaptureURLs
        pendingScreenCaptureURLs.removeAll()
        handleOpenURLs(urls)
''')
begin = text.index('    private static let screenCaptureURLActions: Set<String> = [')
end = text.index('    private func handleURLSchemeAction(', begin)
text = text[:begin] + text[end:]
# This flag still guards one-time overlay prewarming, not URL authorization.
text = text.replace('isReadyForScreenCaptureURLs', 'didPrewarmCapturePath')
text = text.replace('markScreenCaptureURLsReady', 'prewarmCapturePathIfNeeded')
text = text.replace('editors, preferences, Sparkle, etc.', 'editors, preferences, etc.')
path.write_text(text)

path = app / 'UI/Windows/SettingsWindowController.swift'
text = replace_once(path.read_text(), '            window?.toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(initialTabID)\n')
text = replace_once(text, '''        // Window is non-resizable (no .resizable in styleMask), so content size
        // is locked. We also set the content size explicitly after the toolbar
        // is installed (in setupUI) to override NSToolbar's auto-sizing.''',
    '        // Fixed-size Studio layout; setupUI sets the sidebar and content size.')
path.write_text(text)

path = app / 'Services/ImageEncoder.swift'
text = replace_once(path.read_text(),
    '    /// Image bytes remain the first clipboard item; Finder gets a separate file item.',
    '    /// One clipboard item carries image bytes and the Finder file URL.')
path.write_text(text)

path = app / 'UI/Windows/PermissionOnboardingController.swift'
text = path.read_text()
begin = text.index('    /// Check screen recording permission without triggering a system dialog.')
end = text.index('    private func showGranted()', begin)
text = text[:begin] + text[end:]
text = replace_once(text, '        openBtn.keyEquivalent = "\\r"', '        openBtn.keyEquivalent = ""')
text = replace_once(text, '        // Continue button (hidden until granted)', '        // Continue remains available when the OS preflight result is stale.')
text = replace_once(text, '            openBtn.centerXAnchor.constraint(equalTo: cv.centerXAnchor),',
    '            openBtn.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 24),')
text = replace_once(text, '            contBtn.centerXAnchor.constraint(equalTo: cv.centerXAnchor),',
    '            contBtn.leadingAnchor.constraint(equalTo: openBtn.trailingAnchor, constant: 12),')
text = replace_once(text, '            contBtn.widthAnchor.constraint(equalToConstant: 260),',
    '            contBtn.widthAnchor.constraint(equalToConstant: 80),')
path.write_text(text)

# The hidden cache explanation has no remaining consumer in the generated app.
unused_key = 'Copy creates PNG files in this folder so Finder can paste them. You can delete unwanted files here. Deleting the currently copied file prevents further Finder pastes until you copy again.'
assert not any(unused_key in path.read_text() for path in app.rglob('*.swift'))
for path in app.glob('*.lproj/Localizable.strings'):
    text, count = re.subn(r'(?m)^"' + re.escape(unused_key) + r'" = [^\n]*\n', '', path.read_text())
    assert count == 1, path
    path.write_text(text)

# These fork preferences start uppercase and were silently excluded by the
# upstream export filter. Add only the two exact safe keys, not a broad prefix.
path = app / 'Services/SettingsPortability.swift'
text = replace_once(path.read_text(), '        "SUEnableAutomaticChecks",',
    '        "SUEnableAutomaticChecks", "SnapletSettingsAppearance", "SnapletFinderClipboardRetention",')
path.write_text(text)

# Remove Sparkle from BOTH application and test targets, not from an already
# signed bundle (which would break the executable's dynamic-library dependency).
project = source / 'macshot.xcodeproj/project.pbxproj'
text = project.read_text()
sparkle_ids = [
    '2FAA000D2F00000100AA0001', '2F98BCF22F6D83A1006ADDC3',
    '2FAA000B2F00000100AA0001', 'AA0000022F61B60100B71643',
    'AA0000032F61B60100B71643',
]
for identifier in sparkle_ids:
    # An object may include nested requirement dictionaries; locate the next
    # object-level closing brace rather than a nested one.
    pattern = rf'(?m)^\t\t{identifier} /\*[^\n]*?\*/ = (?:\{{[^\n]*\}};|\{{\n.*?^\t\t\}};)\n'
    text, count = re.subn(pattern, '', text, flags=re.S)
    assert count == 1, identifier
    text, count = re.subn(rf'(?m)^\t+{identifier} /\*[^\n]*\*/,\n', '', text)
    assert count == 1, identifier
    assert identifier not in text, identifier
assert 'Sparkle' not in text
project.write_text(text)
resolved = source / 'macshot.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
data = json.loads(resolved.read_text())
pins = data['pins']
data['pins'] = [pin for pin in pins if pin['identity'].lower() != 'sparkle']
assert len(pins) - len(data['pins']) == 1
resolved.write_text(json.dumps(data, indent=2) + '\n')
print('PASS: removed unused update dependency, URL queue, permission wrappers and toolbar assignment; permission buttons separated.')
