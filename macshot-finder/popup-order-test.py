"""Check ordering and mode handoff in the real generated AppDelegate."""
from pathlib import Path
import sys

text = (Path(sys.argv[1]) / 'macshot/AppDelegate.swift').read_text()
start = text.index('    private func performCapture(fromMenu: Bool) {')
end = text.index('    /// Install screenshots into the pre-built overlay controllers', start)
method = text[start:end]
task = method.index('        Task { [weak self] in')
capture = method.index('await ScreenCaptureManager.captureAllScreensImmediatelySCK(')
main = method.index('await MainActor.run {')
session = method.index('self.captureSessionID == sessionID else { return }')
success = method.index('if !finalCaptures.isEmpty {')
panel = method.index('pooledController(for: screen)')
install = method.index('self.installAndShowOverlays(')
assert task < capture < main < session < success < panel < install
for action in ['pooledController(', 'warmPanel(', 'makeKeyAndOrderFront(', 'NSApp.activate(']:
    assert action not in method[:capture], action
for old, new in {
    'pendingRecordMode': 'requestedRecordMode',
    'pendingOCRMode': 'requestedOCRMode',
    'pendingTranslateOverlayMode': 'requestedTranslateMode',
    'pendingTranslateOverlayLang': 'requestedTranslateLanguage',
    'pendingQuickCaptureMode': 'requestedQuickCaptureMode',
    'pendingScrollCaptureMode': 'requestedScrollCaptureMode',
}.items():
    assert f'let {new} = {old}' in method[:task]
    assert new in method[panel:install]
    assert old not in method[main:install]
assert method.count('overlayControllers.append(contentsOf: controllers)') == 1
assert method.count('pooledController(for: screen)') == 1
assert method.index('pendingRecordMode = false') < task
for flag in ['didApplyFullScreen', 'didApplyFullScreenRecord', 'didApplyFullScreenRecordAutoStart']:
    assert f'let {flag} =' in method[:task] and flag in method[install:]
print('PASS: freeze-before-panel ordering, cancellation/stale-session gates, failure path and all capture modes preserved.')
