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
assert 'TC023456-sys / Snaplet' in current
assert 'sw33tLie' in current and 'GPL' in current
print('PASS: existing setting actions retained; sidebar, cards, disclosure, appearance and About metadata integrated.')
