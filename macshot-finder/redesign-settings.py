"""Reproducible native settings redesign applied after fork patches/branding."""
from pathlib import Path
import shutil
import sys

source = Path(sys.argv[1]).resolve()
assets = Path(__file__).resolve().parent
path = source / 'macshot/UI/Windows/SettingsWindowController.swift'
text = path.read_text()

def replace_method(start, end, replacement):
    global text
    assert text.count(start) == 1, start
    begin = text.index(start)
    finish = text.index(end, begin)
    text = text[:begin] + replacement + '\n\n' + text[finish:]

text = text.replace('private var currentTabID: String = "general"', '''private var currentTabID: String = "general"
    private var snapletNavigation: [String: NSButton] = [:]''')
replace_method('    private func setupUI() {', '    private func showTab(id:', r'''    private func setupUI() {
        guard let window = window, let cv = window.contentView else { return }
        window.toolbar = nil
        window.setContentSize(NSSize(width: 810, height: 660))
        applySnapletSettingsAppearance()
        tabContentViews["general"] = makeGeneralTabView()
        tabContentViews["capture"] = makeCaptureTabView()
        tabContentViews["shortcuts"] = makeShortcutsTabView()
        tabContentViews["tools"] = makeToolsTabView()
        tabContentViews["recording"] = makeRecordingTabView()
        #if !OFFLINE
        tabContentViews["uploads"] = makeUploadsTabView()
        #endif
        tabContentViews["about"] = makeAboutTabView()

        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .withinWindow
        sidebar.state = .active
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        let brand = NSTextField(labelWithString: BuildVariant.displayName)
        brand.font = .systemFont(ofSize: 19, weight: .semibold)
        brand.textColor = SnapletSettingsChrome.accent
        let navigation = NSStackView(views: [brand])
        navigation.orientation = .vertical
        navigation.alignment = .leading
        navigation.spacing = 6
        navigation.setCustomSpacing(24, after: brand)
        navigation.translatesAutoresizingMaskIntoConstraints = false
        for (index, def) in Self.tabDefs.enumerated() {
            let button = SnapletNavigationButton(title: L(def.label), target: self, action: #selector(snapletTabSelected(_:)))
            button.tag = index
            button.setButtonType(.toggle)
            button.isBordered = false
            button.alignment = .left
            button.font = .systemFont(ofSize: 13, weight: .medium)
            button.image = NSImage(systemSymbolName: def.symbolName, accessibilityDescription: nil)
            button.imagePosition = .imageLeft
            button.imageScaling = .scaleProportionallyDown
            button.translatesAutoresizingMaskIntoConstraints = false
            button.heightAnchor.constraint(equalToConstant: 36).isActive = true
            navigation.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: navigation.widthAnchor).isActive = true
            snapletNavigation[def.id] = button
        }
        sidebar.addSubview(navigation)
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        tabContentContainer = container
        cv.addSubview(sidebar)
        cv.addSubview(container)
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: cv.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 170),
            navigation.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 14),
            navigation.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -14),
            navigation.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 24),
            container.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            container.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            container.topAnchor.constraint(equalTo: cv.topAnchor),
            container.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
        ])
        showTab(id: "general")
    }

    @objc private func snapletTabSelected(_ sender: NSButton) {
        guard Self.tabDefs.indices.contains(sender.tag) else { return }
        showTab(id: Self.tabDefs[sender.tag].id)
    }

    private func applySnapletSettingsAppearance() {
        switch UserDefaults.standard.string(forKey: "SnapletSettingsAppearance") {
        case "light": window?.appearance = NSAppearance(named: .aqua)
        case "dark": window?.appearance = NSAppearance(named: .darkAqua)
        default: window?.appearance = nil
        }
    }

    @objc private func snapletSettingsAppearanceChanged(_ sender: NSPopUpButton) {
        let values = ["system", "light", "dark"]
        guard values.indices.contains(sender.indexOfSelectedItem) else { return }
        UserDefaults.standard.set(values[sender.indexOfSelectedItem], forKey: "SnapletSettingsAppearance")
        applySnapletSettingsAppearance()
    }''')
text = text.replace('        currentTabID = id', '''        currentTabID = id
        for (tab, button) in snapletNavigation {
            button.state = tab == id ? .on : .off
            button.needsDisplay = true
        }''')
replace_method('    private func finalizeSettingsStack(scroll:', '    private func makeGeneralTabView()', r'''    private func finalizeSettingsStack(scroll: NSScrollView, stack: NSStackView) {
        // Reparent existing controls, preserving all target/action and state bindings.
        let original = stack.arrangedSubviews
        for view in original { stack.removeArrangedSubview(view); view.removeFromSuperview() }
        var rows: [NSView] = []
        func flush() {
            guard !rows.isEmpty else { return }
            let card = SnapletSettingsChrome.card(rows: rows)
            stack.addArrangedSubview(card)
            card.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true
            stack.setCustomSpacing(18, after: card)
            rows.removeAll()
        }
        for view in original {
            if view.identifier?.rawValue == "SnapletSection" {
                flush()
                stack.addArrangedSubview(view)
                stack.setCustomSpacing(8, after: view)
            } else {
                rows.append(view)
            }
        }
        flush()
        scroll.documentView = stack
        let clip = scroll.contentView
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: clip.topAnchor),
            stack.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
        ])
    }''')
text = text.replace('let lbl = NSTextField(labelWithString: text.uppercased())', '''let lbl = NSTextField(labelWithString: text)
        lbl.identifier = NSUserInterfaceItemIdentifier("SnapletSection")''')
text = text.replace('lbl.font = NSFont.systemFont(ofSize: 10, weight: .semibold)', 'lbl.font = NSFont.systemFont(ofSize: 12, weight: .medium)')
text = text.replace('lbl.alignment = .right', 'lbl.alignment = .left')
text = text.replace('constant: Self.labelColumnWidth + 8)', 'constant: 0)')
text = text.replace('    private func indented(_ view: NSView) -> NSView {', '''    private func indented(_ view: NSView) -> NSView {
        if let button = view as? NSButton, let cell = button.cell as? NSButtonCell, cell.buttonType == .switch {
            return SnapletSettingsChrome.toggleRow(button)
        }''')
# Source/maintenance metadata belong in About, not on the General page.
start = text.index('        let updateSource = NSTextField(')
end = text.index('        // ── Appearance', start)
text = text[:start] + text[end:]
text = text.replace('        // Screen Info (debug)', '''        let project = NSButton(title: "TC023456-sys / Snaplet", target: self, action: #selector(openGitHub))
        project.bezelStyle = .inline
        stack.addArrangedSubview(project)

        // Screen Info (debug)''')
text = text.replace('        // Theme preset dropdown', '''        let appearancePopup = NSPopUpButton()
        appearancePopup.addItems(withTitles: [L("Follow System"), L("Light"), L("Dark")])
        let appearanceValues = ["system", "light", "dark"]
        appearancePopup.selectItem(at: appearanceValues.firstIndex(of: UserDefaults.standard.string(forKey: "SnapletSettingsAppearance") ?? "system") ?? 0)
        appearancePopup.target = self
        appearancePopup.action = #selector(snapletSettingsAppearanceChanged(_:))
        stack.addArrangedSubview(labeledRow(L("Appearance"), controls: [appearancePopup]))
        stack.setCustomSpacing(12, after: stack.arrangedSubviews.last!)

        // Theme preset dropdown''')
start = text.index('        stack.addArrangedSubview(indented(iconSymbolRow))')
finish = text.index('        let urlSchemeCheckbox', start)
note_begin = text.index('        let iconNote', start)
note_end = text.index('        stack.addArrangedSubview(indented(iconNote))', note_begin)
note = text[note_begin:note_end]
text = text[:start] + note + '''        stack.addArrangedSubview(SnapletSettingsDisclosure(title: L("Custom symbol"), content: [iconSymbolRow, iconNote]))
        stack.setCustomSpacing(12, after: stack.arrangedSubviews.last!)

''' + text[finish:]
text = text.replace('stack.addArrangedSubview(indented(colorsRow))', 'stack.addArrangedSubview(SnapletSettingsDisclosure(title: L("Custom appearance"), content: [colorsRow]))')
# Notes keep readable type without competing with the primary controls.
text = text.replace('NSFont.systemFont(ofSize: 10)', 'NSFont.systemFont(ofSize: 11)')
path.write_text(text)
shutil.copyfile(assets / 'SnapletSettingsChrome.swift', source / 'macshot/UI/Windows/SnapletSettingsChrome.swift')
translations = {'Follow System': '跟随系统', 'Light': '浅色', 'Dark': '深色', 'Custom appearance': '自定义外观'}
for strings in (source / 'macshot').glob('*.lproj/Localizable.strings'):
    existing = strings.read_text()
    for key, chinese in translations.items():
        if ('"' + key + '" =') not in existing:
            value = chinese if strings.parent.name == 'zh-Hans.lproj' else key
            existing += '\n"' + key + '" = "' + value + '";\n'
    strings.write_text(existing)
print('Native Snaplet settings: sidebar, adaptive section cards, aligned controls and About metadata prepared.')
