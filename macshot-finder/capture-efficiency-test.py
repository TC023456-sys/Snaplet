"""Regression checks against the actual generated capture implementation."""
from pathlib import Path
import sys

root = Path(sys.argv[1]) / 'macshot'
manager = (root / 'Capture/ScreenCaptureManager.swift').read_text()
app = (root / 'AppDelegate.swift').read_text()
view = (root / 'UI/Overlay/OverlayView.swift').read_text()

start = app.index('    private func performCapture(fromMenu: Bool) {')
end = app.index('    /// Install screenshots into the pre-built overlay controllers', start)
capture = app[start:end]
assert 'let targetScreen = (pendingFullScreen && !pendingRecordMode)' in capture
assert '? (mouseScreen ?? NSScreen.main) : nil' in capture
assert 'makeImmediateCaptureContext(targetScreen: targetScreen)' in capture
assert 'targetScreen: targetScreen,' in capture
assert 'for capture in finalCaptures {' in capture
assert 'let screen = capture.screen' in capture
assert 'for screen in screens {' not in capture
assert capture.index('captureSessionID == sessionID') < capture.index('for capture in finalCaptures')
# Default nil preserves region capture/recording and other call sites.
assert manager.count('targetScreen: NSScreen? = nil') == 2
assert 'screens: targetScreen.map { [$0] } ?? screens' in manager
assert 'if targetScreen == nil || screen == targetScreen' in manager
rect = manager[manager.index('    private static func captureAllScreensImmediatelySCKRect('):]
assert rect.index('let primaryHeight = primaryScreen.frame.maxY') < rect.index('let captureScreens')
assert 'y: primaryHeight - appKitFrame.maxY' in rect
assert 'for (index, screen) in captureScreens.enumerated()' in rect
assert 'guard captures.count == captureScreens.count else' in rect
assert 'config.width = Int(rect.width * screen.backingScaleFactor)' in rect
assert 'config.height = Int(rect.height * screen.backingScaleFactor)' in rect
prewarm = manager[manager.index('    static func prewarm() {'):manager.index('    static func makeImmediateCaptureContext(')]
assert prewarm.index('if #available(macOS 26.0, *) { return }') < prewarm.index('Task {')
reset = view[view.index('    func reset() {'):view.index('// MARK: - NSTextViewDelegate')]
assert 'customBeautifyBackground = nil' in reset
assert 'ensureCustomBeautifyBackgroundLoaded()' not in reset
assert 'if screenshotImage != nil { ensureCustomBeautifyBackgroundLoaded() }' in view
print('PASS: targeted still capture, all-screen region/record defaults, Retina/origin, fallback scope, idle background and prewarm.')
