"""Verify rebranded source has no upstream brand art left in bundled assets."""
import hashlib
import json
from pathlib import Path
import plistlib
import re
import sys
import xml.etree.ElementTree as ET

source = Path(sys.argv[1])
original = Path(sys.argv[2])
app = source / 'macshot'
catalog = app / 'Assets.xcassets'
assets = Path(__file__).resolve().parent
old_catalog = original / 'macshot/Assets.xcassets'
old_hashes = {
    hashlib.sha256(p.read_bytes()).hexdigest()
    for p in old_catalog.rglob('*') if p.suffix in {'.svg', '.png'}
}
new_files = [p for p in catalog.rglob('*') if p.suffix in {'.svg', '.png'}]
assert len(new_files) == 13, [str(p) for p in new_files]
assert not any(hashlib.sha256(p.read_bytes()).hexdigest() in old_hashes for p in new_files)
for manifest in catalog.rglob('Contents.json'):
    for image in json.loads(manifest.read_text()).get('images', []):
        if 'filename' in image:
            assert (manifest.parent / image['filename']).is_file(), manifest
for name, filename, reference in [
    ('StatusBarIcon', 'snaplet-status.svg', 'SnapletStatusBar.svg'),
    ('Logo', 'snaplet-logo.png', 'Snaplet.png'),
    ('PermissionsGuide', 'snaplet-permission.svg', 'SnapletPermissionGuide.svg'),
]:
    assert (catalog / (name + '.imageset') / filename).read_bytes() == (assets / reference).read_bytes()
status = json.loads((catalog / 'StatusBarIcon.imageset/Contents.json').read_text())
assert status['properties']['template-rendering-intent'] == 'template'
for name in ['SnapletStatusBar.svg', 'SnapletPermissionGuide.svg']:
    ET.parse(assets / name)
info = plistlib.loads((app / 'Info.plist').read_bytes())
assert info['CFBundleName'] == 'Snaplet'
assert info.get('CFBundleIdentifier') == plistlib.loads((original / 'macshot/Info.plist').read_bytes()).get('CFBundleIdentifier')
identity_pattern = r'PRODUCT_BUNDLE_IDENTIFIER = [^;]+;'
assert re.findall(identity_pattern, (source / 'macshot.xcodeproj/project.pbxproj').read_text()) == re.findall(identity_pattern, (original / 'macshot.xcodeproj/project.pbxproj').read_text())
delegate = (app / 'AppDelegate.swift').read_text()
assert 'NSImage(named: "StatusBarIcon")' in delegate
assert 'button.title = "macshot"' not in delegate
guide = (app / 'UI/Windows/PermissionOnboardingController.swift').read_text()
assert 'camera.viewfinder' not in guide
assert '200.0 / 360.0' in guide
print('PASS: all 13 bundled brand images replaced; template, references, fallback and identity checked.')
