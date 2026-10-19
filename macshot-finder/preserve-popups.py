"""Take the screenshot before creating, warming or focusing selection panels.

Applied to the pinned upstream source after the other fork transformations.
"""
from pathlib import Path
import sys

path = Path(sys.argv[1]) / 'macshot/AppDelegate.swift'
text = path.read_text()
begin = text.index('    private func performCapture(fromMenu: Bool) {')
end = text.index('    /// Install screenshots into the pre-built overlay controllers', begin)
method = text[begin:end]

start = method.index('        // Pull (don\'t construct) overlay controllers')
finish = method.index('        pendingRecordMode = false', start)
controllers = method[start:finish]
# Deferred work must use immutable snapshots, not flags cleared before the await.
modes = {
    'pendingRecordMode': 'requestedRecordMode',
    'pendingOCRMode': 'requestedOCRMode',
    'pendingTranslateOverlayMode': 'requestedTranslateMode',
    'pendingTranslateOverlayLang': 'requestedTranslateLanguage',
    'pendingQuickCaptureMode': 'requestedQuickCaptureMode',
    'pendingScrollCaptureMode': 'requestedScrollCaptureMode',
}
snapshots = ''.join(f'        let {new} = {old}\n' for old, new in modes.items())
method = method[:start] + snapshots + '\n' + method[finish:]
for old, new in modes.items():
    controllers = controllers.replace(old, new)
for member in ['measureCaptureTiming', 'pooledController', 'captureTimingTrace', 'capturedWindowTitle', 'overlayControllers']:
    controllers = controllers.replace(member, 'self.' + member)
controllers = controllers.replace(
    "        // Pull (don't construct) overlay controllers from the persistent pool.\n"
    "        // Each controller's NSPanel was created and warmed at launch / pool\n"
    "        // rebuild, so WindowServer's per-window cache is already hot.\n",
    '        // The pixels are already frozen; a cold pool may now warm panels safely.\n')
assert controllers.count('pooledController(for: screen)') == 1
# Indent inside MainActor.run and an image-success branch. No panel is created
# if capture failed or an obsolete/cancelled session returned from its await.
controllers = controllers.replace('        var controllers: [OverlayWindowController] = []\n', '')
controllers = '\n'.join('            ' + line if line else '' for line in controllers.rstrip().split('\n'))
anchor = '''                guard let self = self, self.isCapturing,
                      self.captureSessionID == sessionID else { return }
'''
assert method.count(anchor) == 1
method = method.replace(anchor, anchor + '''                var controllers: [OverlayWindowController] = []
                if !finalCaptures.isEmpty {
''' + controllers + '\n                }\n')
method = method.replace('''        // Kick off the screenshot capture on a background queue. Window
        // creation runs on main concurrently — both costs are paid in parallel.
        // CGWindowListCreateImage is used because it preserves transient UI
        // (menu extras, app menus, Raycast-style panels) that disappears once
        // anything steals focus. Overlay windows haven't been ordered-front yet
        // so they won't appear in the capture.''', '''        // Preserve transient website UI before any selection-panel creation,
        // invisible warmPanel/orderFront, or focus acquisition can dismiss it.
        // This is especially important after idle cleanup empties the pool.''')
method = method.replace('''        // Run the screenshot capture now and dispatch back to main when done.
        // Window creation above already ran in parallel with the prep that the
        // background work still has to do.''', '''        // Capture first; only prepare selection windows after a live session
        // has received its screenshot. Keep keyboard routing unchanged.''')
assert method.count('pooledController(for: screen)') == 1
text = text[:begin] + method + text[end:]
path.write_text(text)
print('PASS: screenshot acquisition precedes overlay creation/warming; capture modes and session guards preserved.')
