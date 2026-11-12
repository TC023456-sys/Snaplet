from pathlib import Path
import shutil
import sys

root = Path(sys.argv[1])
support = Path(__file__).parent
shutil.copy2(support / 'WindowSwitcher.swift', root / 'macshot/Services/WindowSwitcher.swift')
app = root / 'macshot/AppDelegate.swift'
text = app.read_text()
anchor = '        registerHotkey()\n'
assert text.count(anchor) == 2
text = text.replace(anchor, anchor + '''        WindowSwitcher.shared.canPresent = { [weak self] in
            guard let self = self else { return false }
            return !self.isCapturing && self.recordingEngine == nil && !self.overlayControllers.contains(where: { $0.hasInteractiveWindow })
        }
        WindowSwitcher.shared.start()
''', 1)
anchor = '        let prefsItem = NSMenuItem(title: L("Settings..."),'
assert text.count(anchor) == 1
text = text.replace(anchor, '        WindowSwitcher.shared.appendMenu(to: menu)\n        menu.addItem(NSMenuItem.separator())\n\n' + anchor)
anchor = '    private func startCapture(fromMenu: Bool = false) {\n'
assert text.count(anchor) == 1
text = text.replace(anchor, anchor + '        WindowSwitcher.shared.cancelForCapture()\n')
app.write_text(text)
hotkey = root / 'macshot/Services/HotkeyManager.swift'
text = hotkey.read_text()
anchor = '                if let slot = HotkeySlot(rawValue: Int(hotkeyID.id))'
assert text.count(anchor) == 1
text = text.replace(anchor, '                guard hotkeyID.signature == 0x4D53_4854 else { return OSStatus(eventNotHandledErr) }\n\n' + anchor)
hotkey.write_text(text)
print('Integrated WindowSwitcher into Snaplet; screenshot hotkey values and capture implementation preserved.')
