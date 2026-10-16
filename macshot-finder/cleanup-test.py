"""Regression checks for the final generated source, not just patch text."""
import json
from pathlib import Path
import subprocess
import sys

source = Path(sys.argv[1])
original = Path(sys.argv[2])
app = source / 'macshot'
delegate = (app / 'AppDelegate.swift').read_text()
for unused in ['pendingScreenCaptureURLs', 'screenCaptureURLActions', 'isReadyForScreenCaptureURLs', 'markScreenCaptureURLsReady']:
    assert unused not in delegate, unused
assert 'guard !didPrewarmCapturePath else { return }' in delegate
assert 'ForkUpdateService.shared.start()' in delegate
assert 'handleURLSchemeAction(url)' in delegate
guide = (app / 'UI/Windows/PermissionOnboardingController.swift').read_text()
for unused in ['checkPermissionSync', 'hasScreenRecordingPermission']:
    assert unused not in guide, unused
assert 'CGPreflightScreenCaptureAccess()' in guide  # Actual polling is live.
assert 'onContinue?()' in guide and 'onClose?()' in guide
assert guide.count('keyEquivalent = "\\r"') == 2  # Continue creation + granted state.
settings = (app / 'UI/Windows/SettingsWindowController.swift').read_text()
assert 'selectedItemIdentifier' not in settings
assert 'separate file item' not in (app / 'Services/ImageEncoder.swift').read_text()
for strings in app.glob('*.lproj/Localizable.strings'):
    assert '"Copy creates PNG files in this folder so Finder can paste them.' not in strings.read_text(), strings
portable = (app / 'Services/SettingsPortability.swift').read_text()
assert '"SnapletSettingsAppearance", "SnapletFinderClipboardRetention"' in portable

relative = 'macshot.xcodeproj/project.pbxproj'
def project_json(path):
    return json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(path)]))
current = project_json(source / relative)
baseline = project_json(original / relative)
removed = set(baseline['objects']) - set(current['objects'])
assert len(removed) == 5
assert all('Sparkle' in json.dumps(baseline['objects'][key]) or
           baseline['objects'][key].get('productRef') in removed for key in removed)
# Every retained object is identical apart from references to the removed nodes.
def without_removed(value):
    if isinstance(value, dict):
        return {key: without_removed(item) for key, item in value.items()}
    if isinstance(value, list):
        return [without_removed(item) for item in value if not isinstance(item, str) or item not in removed]
    return value
for key, obj in current['objects'].items():
    assert obj == without_removed(baseline['objects'][key]), key
assert current['rootObject'] == baseline['rootObject']
relative = 'macshot.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
old = json.loads((original / relative).read_text())
new = json.loads((source / relative).read_text())
assert new['pins'] == [pin for pin in old['pins'] if pin['identity'].lower() != 'sparkle']
assert any('webp' in pin['identity'].lower() for pin in new['pins'])
print('PASS: removed exactly 5 Sparkle project objects; all other project settings/dependencies preserved; live capture and permission paths retained.')
