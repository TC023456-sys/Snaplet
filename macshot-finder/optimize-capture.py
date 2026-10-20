"""Reduce idle image retention and unnecessary full-display capture work.

Apply after preserve-popups.py to the pinned upstream tree.
"""
from pathlib import Path
import sys

root = Path(sys.argv[1]) / 'macshot'

def replace(text, old, new):
    assert text.count(old) == 1, f'Expected one optimization anchor: {old[:100]}'
    return text.replace(old, new)

path = root / 'Capture/ScreenCaptureManager.swift'
text = path.read_text()
text = replace(text, '    static func prewarm() {\n',
    '    static func prewarm() {\n'
    '        // Rect screenshots need no shareable-window enumeration.\n'
    '        if #available(macOS 26.0, *) { return }\n')
text = replace(text,
    'static func makeImmediateCaptureContext(timing:',
    'static func makeImmediateCaptureContext(targetScreen: NSScreen? = nil, timing:')
text = replace(text, '            screens: screens,\n            mainHeight:',
    '            screens: targetScreen.map { [$0] } ?? screens,\n            mainHeight:')
text = replace(text,
    '    static func captureAllScreensImmediatelySCK(\n        timing:',
    '    static func captureAllScreensImmediatelySCK(\n        targetScreen: NSScreen? = nil,\n        timing:')
text = replace(text, '                showsCursor: showsCursor,\n                timing: timing',
    '                targetScreen: targetScreen,\n                showsCursor: showsCursor,\n                timing: timing')
start = text.index('    static func captureAllScreensImmediatelySCK(')
end = text.index('    private static func captureAllScreensImmediatelySCKRect(', start)
method = text[start:end]
method = replace(method, '                pairs.append((display, screen))\n',
    '                if targetScreen == nil || screen == targetScreen {\n'
    '                    pairs.append((display, screen))\n'
    '                }\n')
text = text[:start] + method + text[end:]
text = replace(text,
    '    private static func captureAllScreensImmediatelySCKRect(\n        showsCursor:',
    '    private static func captureAllScreensImmediatelySCKRect(\n        targetScreen: NSScreen?,\n        showsCursor:')
# Keep the primary display origin even when targeting a non-primary monitor.
text = replace(text, '        let primaryHeight = primaryScreen.frame.maxY\n',
    '        let primaryHeight = primaryScreen.frame.maxY\n'
    '        let captureScreens = targetScreen.map { [$0] } ?? screens\n')
start = text.index('    private static func captureAllScreensImmediatelySCKRect(')
end = text.index('    private static func captureScreenshotOutput(', start)
method = text[start:end]
method = replace(method, 'screens.enumerated()', 'captureScreens.enumerated()')
method = replace(method, 'captures.count == screens.count', 'captures.count == captureScreens.count')
text = text[:start] + method + text[end:]
path.write_text(text)

path = root / 'AppDelegate.swift'
text = path.read_text()
start = text.index('    private func performCapture(fromMenu: Bool) {')
end = text.index('    /// Install screenshots into the pre-built overlay controllers', start)
method = text[start:end]
method = replace(method, '        // Preserve transient website UI',
    '        // Full-screen stills need only the pointer display; region capture\n'
    '        // and recording retain all displays and cross-screen selection.\n'
    '        let targetScreen = (pendingFullScreen && !pendingRecordMode)\n'
    '            ? (mouseScreen ?? NSScreen.main) : nil\n\n'
    '        // Preserve transient website UI')
method = replace(method, 'ScreenCaptureManager.makeImmediateCaptureContext()',
    'ScreenCaptureManager.makeImmediateCaptureContext(targetScreen: targetScreen)')
method = replace(method, 'ScreenCaptureManager.captureAllScreensImmediatelySCK(\n',
    'ScreenCaptureManager.captureAllScreensImmediatelySCK(\n'
    '                    targetScreen: targetScreen,\n')
method = replace(method, '                    for screen in screens {',
    '                    for capture in finalCaptures {\n'
    '                        let screen = capture.screen')
text = text[:start] + method + text[end:]
path.write_text(text)

path = root / 'UI/Overlay/OverlayView.swift'
text = path.read_text()
text = replace(text,
    '        // The custom-style background is loaded here (not lazily in the\n'
    '        // beautifyConfig getter) so reads during draw never mutate state.\n'
    '        customBeautifyBackground = nil\n'
    '        ensureCustomBeautifyBackgroundLoaded()\n',
    '        // Release the session background while idle. screenshotImage.didSet\n'
    '        // loads it before the next capture/editor clean-state snapshot.\n'
    '        customBeautifyBackground = nil\n')
path.write_text(text)
print('PASS: capture scope, macOS 26 prewarm and idle background optimized.')
