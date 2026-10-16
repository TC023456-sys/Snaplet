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
    private var snapletNavigation: [String: NSButton] = [:]
    private var snapletPageHeading: NSTextField?''')
replace_method('    private func setupUI() {', '    private func showTab(id:', r'''    private func setupUI() {
        guard let window = window, let cv = window.contentView else { return }
        window.toolbar = nil
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.setContentSize(NSSize(width: 880, height: 650))
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

        let sidebar = SnapletSettingsCard()
        sidebar.isSidebar = true
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        let brand = NSTextField(labelWithString: BuildVariant.displayName)
        brand.font = .systemFont(ofSize: 18, weight: .medium)
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
            button.heightAnchor.constraint(equalToConstant: 40).isActive = true
            navigation.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: navigation.widthAnchor).isActive = true
            snapletNavigation[def.id] = button
        }
        sidebar.addSubview(navigation)
        let page = SnapletSettingsCard()
        page.translatesAutoresizingMaskIntoConstraints = false
        let heading = NSTextField(labelWithString: L("General"))
        heading.font = .systemFont(ofSize: 24, weight: .medium)
        heading.translatesAutoresizingMaskIntoConstraints = false
        snapletPageHeading = heading
        page.addSubview(heading)
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        tabContentContainer = container
        cv.addSubview(sidebar)
        cv.addSubview(page)
        page.addSubview(container)
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: cv.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 190),
            navigation.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 14),
            navigation.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -14),
            navigation.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 68),
            page.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            page.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            page.topAnchor.constraint(equalTo: cv.topAnchor),
            page.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
            heading.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: 32),
            heading.topAnchor.constraint(equalTo: page.topAnchor, constant: 44),
            container.leadingAnchor.constraint(equalTo: page.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: page.trailingAnchor),
            container.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 20),
            container.bottomAnchor.constraint(equalTo: page.bottomAnchor),
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
        snapletPageHeading?.stringValue = L(Self.tabDefs.first(where: { $0.id == id })?.label ?? "General")
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
            card.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -64).isActive = true
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
text = text.replace('NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)', 'NSEdgeInsets(top: 8, left: 32, bottom: 24, right: 32)')
text = text.replace('constant: Self.labelColumnWidth + 8)', 'constant: 0)')
text = text.replace('    private func indented(_ view: NSView) -> NSView {', '''    private func indented(_ view: NSView) -> NSView {
        let rightAlignedToggles: [NSButton?] = [launchAtLoginCheckbox, hideMenuBarIconCheckbox, autoUpdateCheckbox, betaUpdateCheckbox]
        if let button = view as? NSButton, rightAlignedToggles.contains(where: { $0 === button }) {
            return SnapletSettingsChrome.toggleRow(button)
        }''')
# Let ordinary row labels expand, keeping native controls on the trailing edge.
text = text.replace('        lbl.widthAnchor.constraint(equalToConstant: Self.labelColumnWidth).isActive = true', '''        lbl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        lbl.setContentHuggingPriority(.defaultLow, for: .horizontal)''')
text = text.replace('let row = NSStackView(views: [lbl] + controls)', 'let row = NSStackView(views: [lbl, NSView()] + controls)')
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
cache_anchor = '        stack.addArrangedSubview(indented(clipboardNote))'
assert text.count(cache_anchor) == 1
text = text.replace(cache_anchor, cache_anchor + '\n        stack.addArrangedSubview(SnapletFinderCacheControls())')
# Keep safety / data-loss / credentials explanations; remove redundant General copy.
for redundant in ['langNote', 'hideNote', 'backupNote', 'downscaleNote', 'orderNote', 'providerNote', 'menuOrderNote']:
    text = text.replace(f'        stack.addArrangedSubview(indented({redundant}))', f'        // {redundant}: redundant explanation omitted from the compact layout.')
text = text.replace('        stack.addArrangedSubview(indented(clipboardPath))', '        // Cache path stays available via Open in Finder.')
text = text.replace(cache_anchor, '        // Cache cleanup is explained by SnapletFinderCacheControls.')

# Reorder General without rebuilding any control or changing its saved value.
general_start = text.index('    private func makeGeneralTabView()')
general_finish = text.index('    // MARK: - Settings Backup actions', general_start)
general = text[general_start:general_finish]
general = general.replace('        finalizeSettingsStack(scroll: scroll, stack: stack)', '''        snapletArrangeGeneral(stack: stack, appearancePopup: appearancePopup)
        finalizeSettingsStack(scroll: scroll, stack: stack)''')
text = text[:general_start] + general + text[general_finish:]
helper = r'''    private func snapletArrangeGeneral(stack: NSStackView, appearancePopup: NSPopUpButton) {
        let original = stack.arrangedSubviews
        func contains(_ view: NSView, _ target: NSView) -> Bool {
            view === target || view.subviews.contains { contains($0, target) }
        }
        var used = Set<ObjectIdentifier>()
        func take(_ target: NSView) -> NSView? {
            guard let row = original.first(where: { contains($0, target) }) else { return nil }
            used.insert(ObjectIdentifier(row))
            return row
        }
        let startup = [take(launchAtLoginCheckbox), take(hideMenuBarIconCheckbox)].compactMap { $0 }
        let appearance = [take(appearancePopup), take(themePresetPopup)].compactMap { $0 }
        let languageUpdates = [take(languagePopup), take(autoUpdateCheckbox)].compactMap { $0 }
        for row in original { stack.removeArrangedSubview(row); row.removeFromSuperview() }
        func addSection(_ title: String, _ rows: [NSView]) {
            stack.addArrangedSubview(sectionHeader(title))
            for row in rows { stack.addArrangedSubview(row) }
        }
        addSection(L("Startup & Behavior"), startup)
        addSection(L("Appearance"), appearance)
        addSection(L("Language & Updates"), languageUpdates)
        let advanced = original.filter { !used.contains(ObjectIdentifier($0)) && $0.identifier?.rawValue != "SnapletSection" }
        stack.addArrangedSubview(SnapletSettingsDisclosure(title: L("Advanced options"), content: advanced))
    }

'''
text = text.replace('    // MARK: - Settings Backup actions', helper + '    // MARK: - Settings Backup actions')
text = text.replace('NSFont.systemFont(ofSize: 10)', 'NSFont.systemFont(ofSize: 11)')
path.write_text(text)
shutil.copyfile(assets / 'SnapletSettingsChrome.swift', source / 'macshot/UI/Windows/SnapletSettingsChrome.swift')
translations = {'Follow System': '跟随系统', 'Light': '浅色', 'Dark': '深色', 'Custom appearance': '自定义外观', 'Startup & Behavior': '启动与行为', 'Language & Updates': '语言与更新', 'Advanced options': '高级选项'}
for strings in (source / 'macshot').glob('*.lproj/Localizable.strings'):
    existing = strings.read_text()
    for key, chinese in translations.items():
        if ('"' + key + '" =') not in existing:
            value = chinese if strings.parent.name == 'zh-Hans.lproj' else key
            existing += '\n"' + key + '" = "' + value + '";\n'
    strings.write_text(existing)
print('Native Snaplet settings: sidebar, adaptive section cards, aligned controls and About metadata prepared.')
