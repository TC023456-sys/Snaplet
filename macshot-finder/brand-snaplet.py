"""Reproducible display-only rebrand; bundle ID, Swift module and data paths stay unchanged."""
import json
import plistlib
from pathlib import Path
import re
import shutil
import subprocess
import sys

source = Path(sys.argv[1]).resolve()
assets = Path(__file__).resolve().parent
app = source / 'macshot'
variant = app / 'Services/BuildVariant.swift'
text = variant.read_text()
assert 'static let displayName = "macshot"' in text
variant.write_text(text.replace('"macshot Offline"', '"Snaplet Offline"').replace('"macshot"', '"Snaplet"'))

# Keep localization lookup keys, URL schemes, storage paths and copyright intact.
for path in app.glob('*.lproj/Localizable.strings'):
    text = path.read_text()
    def rename_value(match):
        value = re.sub(r'\bmacshot\b(?!://)', 'Snaplet', match.group(2), flags=re.I)
        return match.group(1) + value + match.group(3)
    path.write_text(re.sub(r'(^"[^\n]*?"\s*=\s*")(.*?)(";\s*$)', rename_value, text, flags=re.M))

delegate = app / 'AppDelegate.swift'
text = delegate.read_text()
text = text.replace('withTitle: "About macshot"', 'withTitle: "About Snaplet"')
text = text.replace('withTitle: "Quit macshot"', 'withTitle: "Quit Snaplet"')
text = text.replace('accessibilityDescription: "macshot"', 'accessibilityDescription: "Snaplet"')
text = text.replace('button.title = "macshot"', 'button.title = "Snaplet"')
delegate.write_text(text)

info = app / 'Info.plist'
data = plistlib.loads(info.read_bytes())
data['CFBundleName'] = 'Snaplet'
data['CFBundleDisplayName'] = 'Snaplet'
for key in ['Privacy - Screen Capture Usage Description', 'NSMicrophoneUsageDescription', 'NSCameraUsageDescription']:
    data[key] = data[key].replace('macshot', 'Snaplet')
info.write_bytes(plistlib.dumps(data, sort_keys=False))

iconset = app / 'Assets.xcassets/AppIcon.appiconset'
images = json.loads((iconset / 'Contents.json').read_text())['images']
for entry in images:
    pixels = int(entry['size'].split('x')[0]) * int(entry['scale'][0])
    subprocess.run(['sips', '-z', str(pixels), str(pixels), str(assets / 'Snaplet.png'), '--out', str(iconset / entry['filename'])], check=True, stdout=subprocess.DEVNULL)

# Replace all upstream brand artwork, including assets unused by current views.
# Keep the established asset names so every existing consumer sees the new art.
def replace_imageset(name, filename, source_file, template=False):
    directory = app / 'Assets.xcassets' / (name + '.imageset')
    metadata = json.loads((directory / 'Contents.json').read_text())
    old_files = [entry.get('filename') for entry in metadata['images']]
    metadata['images'] = [{'filename': filename, 'idiom': 'mac', 'scale': '1x'}]
    metadata['properties'] = {'preserves-vector-representation': True} if filename.endswith('.svg') else {}
    if template:
        metadata['properties']['template-rendering-intent'] = 'template'
    shutil.copyfile(assets / source_file, directory / filename)
    (directory / 'Contents.json').write_text(json.dumps(metadata, indent=2) + '\n')
    for old in old_files:
        if old and old != filename:
            target = directory / old
            assert target.parent == directory and target.is_file()
            target.unlink()

replace_imageset('StatusBarIcon', 'snaplet-status.svg', 'SnapletStatusBar.svg', template=True)
replace_imageset('Logo', 'snaplet-logo.png', 'Snaplet.png')
replace_imageset('PermissionsGuide', 'snaplet-permission.svg', 'SnapletPermissionGuide.svg')

onboarding = app / 'UI/Windows/PermissionOnboardingController.swift'
text = onboarding.read_text()
text = text.replace('NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: nil)', 'NSImage(named: "Logo")')
text = text.replace('// Image aspect ratio: 1405 × 892', '// Snaplet permission illustration: 360 × 200')
text = text.replace('892.0 / 1405.0', '200.0 / 360.0')
onboarding.write_text(text)
print('Snaplet branding prepared: 10 app icon sizes, menu bar, logo and permission guide; stable bundle ID retained.')
