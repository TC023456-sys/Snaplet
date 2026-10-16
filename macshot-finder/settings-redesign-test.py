"""Source integration checks; does not substitute for a complete Release build."""
from pathlib import Path
import re
import sys

source = Path(sys.argv[1])
original = Path(sys.argv[2])
relative = 'macshot/UI/Windows/SettingsWindowController.swift'
current = (source / relative).read_text()
upstream = (original / relative).read_text()
# All existing setting action methods remain; only the window chrome is replaced.
actions = lambda text: set(re.findall(r'@objc\s+(?:private\s+)?func\s+(\w+)', text))
assert actions(upstream) <= actions(current), sorted(actions(upstream) - actions(current))
for method in ['makeGeneralTabView', 'makeCaptureTabView', 'makeShortcutsTabView', 'makeToolsTabView', 'makeRecordingTabView', 'makeUploadsTabView', 'makeAboutTabView', 'rebuildAllTabsAfterImport']:
    assert method in current
assert 'window.toolbar = toolbar' not in current
assert 'let footerStack' not in current
assert 'let updateSource = NSTextField' not in current
assert 'snapletNavigation' in current
assert 'applySnapletSettingsAppearance()' in current
assert 'SnapletSettingsDisclosure' in current
assert 'SnapletFinderCacheControls()' in current
chrome = (source / 'macshot/UI/Windows/SnapletSettingsChrome.swift').read_text()
assert 'x: 42' in chrome and 'let counts = [1, 5, 10, 20]' in chrome
assert 'SnapletFinderClipboardRetention' in chrome
assert 'window.titleVisibility = .hidden' in current
assert 'window.titlebarAppearsTransparent = true' in current
assert 'snapletPageHeading?.stringValue' in current
assert 'snapletArrangeGeneral(stack: stack, appearancePopup: appearancePopup)' in current
assert 'let advanced = original.filter' in current
assert 'SnapletSwitchCell' in chrome and 'button.target = oldTarget' in chrome
assert 'let box = NSView()' in chrome
assert 'path.stroke()' not in chrome
assert 'override var wantsDefaultClipping: Bool { true }' in chrome
assert 'bounds.fill()' in chrome and 'dirtyRect.fill()' not in chrome
assert 'stack.addArrangedSubview(indented(langNote))' not in current
assert 'stack.addArrangedSubview(indented(backupNote))' not in current
assert 'stack.addArrangedSubview(indented(browserElementSnapNote))' in current
assert 'stack.addArrangedSubview(indented(hideHUDNote))' in current
assert 'TC023456-sys / Snaplet' in current
assert 'sw33tLie' in current and 'GPL' in current
print('PASS: existing actions retained; Studio sidebar, hidden titlebar, concise General groups, native toggle routing, safety notes and About attribution integrated.')
