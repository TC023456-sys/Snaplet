import AppKit

/// Settings chrome only. Existing controls and their target/action remain owned
/// by SettingsWindowController; no preferences or capture state are changed.
@MainActor
enum SnapletSettingsChrome {
    static let accent = NSColor(name: NSColor.Name("SnapletSettingsAccent")) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark ? NSColor(calibratedRed: 0.65, green: 0.83, blue: 0.71, alpha: 1)
                    : NSColor(calibratedRed: 0.16, green: 0.37, blue: 0.28, alpha: 1)
    }
    static let background = NSColor(name: NSColor.Name("SnapletStudioBackground")) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.11, green: 0.12, blue: 0.12, alpha: 1)
            : NSColor(calibratedRed: 0.985, green: 0.985, blue: 0.977, alpha: 1)
    }
    static let sidebar = NSColor(name: NSColor.Name("SnapletStudioSidebar")) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.135, green: 0.155, blue: 0.145, alpha: 1)
            : NSColor(calibratedRed: 0.945, green: 0.953, blue: 0.937, alpha: 1)
    }

    static func card(rows: [NSView]) -> NSView {
        let box = NSView()
        let content = NSStackView(views: rows)
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 14
        content.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: box.topAnchor, constant: 10),
            content.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -10),
            content.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: box.trailingAnchor),
        ])
        for (index, row) in rows.enumerated() {
            row.translatesAutoresizingMaskIntoConstraints = false
            row.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
            if index < rows.count - 1 {
                let line = NSBox()
                line.boxType = .separator
                content.insertArrangedSubview(line, at: content.arrangedSubviews.firstIndex(of: row)! + 1)
                line.translatesAutoresizingMaskIntoConstraints = false
                line.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
            }
        }
        return box
    }

    static func toggleRow(_ button: NSButton) -> NSView {
        let label = NSTextField(wrappingLabelWithString: button.title)
        label.font = .systemFont(ofSize: 13)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.setAccessibilityLabel(button.title)
        let oldState = button.state
        let oldTarget = button.target
        let oldAction = button.action
        let oldEnabled = button.isEnabled
        let switchCell = SnapletSwitchCell(textCell: "")
        switchCell.setButtonType(.switch)
        button.cell = switchCell
        button.target = oldTarget
        button.action = oldAction
        button.state = oldState
        button.isEnabled = oldEnabled
        button.title = ""
        button.widthAnchor.constraint(equalToConstant: 34).isActive = true
        button.heightAnchor.constraint(equalToConstant: 22).isActive = true
        button.setContentHuggingPriority(.required, for: .horizontal)
        let row = NSStackView(views: [label, NSView(), button])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }
}

/// Retains NSButton's keyboard, accessibility and existing target/action API.
@MainActor
final class SnapletSwitchCell: NSButtonCell {
    override var cellSize: NSSize { NSSize(width: 34, height: 22) }
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        let track = NSRect(x: cellFrame.midX - 16, y: cellFrame.midY - 9, width: 32, height: 18)
        (state == .on ? SnapletSettingsChrome.accent : NSColor.separatorColor).setFill()
        NSBezierPath(roundedRect: track, xRadius: 9, yRadius: 9).fill()
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: track.minX + (state == .on ? 16 : 3), y: track.minY + 3, width: 12, height: 12)).fill()
    }
}

@MainActor
final class SnapletSettingsCard: NSView {
    var isSidebar = false
    override var wantsDefaultClipping: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        (isSidebar ? SnapletSettingsChrome.sidebar : SnapletSettingsChrome.background).setFill()
        bounds.fill()
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

@MainActor
final class SnapletNavigationButton: NSButton {
    override func draw(_ dirtyRect: NSRect) {
        if state == .on {
            let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            (dark ? SnapletSettingsChrome.accent.withAlphaComponent(0.09) : NSColor.controlBackgroundColor).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8).fill()
        }
        contentTintColor = state == .on ? SnapletSettingsChrome.accent : .secondaryLabelColor
        // Fixed icon column and label origin, independent of SF Symbol width.
        let tint = contentTintColor ?? .labelColor
        if let image {
            let icon = image.copy() as! NSImage
            icon.isTemplate = true
            let size = icon.size
            let scale = min(18 / max(size.width, 1), 18 / max(size.height, 1))
            let rect = NSRect(x: 12 + (20 - size.width * scale) / 2,
                              y: (bounds.height - size.height * scale) / 2,
                              width: size.width * scale, height: size.height * scale)
            icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1,
                      respectFlipped: true, hints: nil)
        }
        let text = NSAttributedString(string: title, attributes: [
            .font: font ?? NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: tint
        ])
        text.draw(at: NSPoint(x: 42, y: (bounds.height - text.size().height) / 2))
        if state == .on {
            tint.setFill()
            NSBezierPath(ovalIn: NSRect(x: bounds.width - 14, y: bounds.midY - 2, width: 4, height: 4)).fill()
        }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// Independent from screenshot-history retention. Applies on the next copy,
/// so changing this option never breaks the current Finder clipboard file.
@MainActor
final class SnapletFinderCacheControls: NSStackView {
    private let popup = NSPopUpButton()
    private let counts = [1, 5, 10, 20]
    private let key = "SnapletFinderClipboardRetention"
    init() {
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 6
        let chinese = Locale.preferredLanguages.first?.hasPrefix("zh") == true
        let label = NSTextField(labelWithString: chinese ? "Finder 复制缓存保留数量：" : "Finder copy cache limit:")
        popup.addItems(withTitles: counts.map { chinese ? "最近 \($0) 张" : "Latest \($0) image(s)" })
        let value = UserDefaults.standard.object(forKey: key) as? Int ?? 1
        popup.selectItem(at: counts.firstIndex(of: value) ?? 0)
        popup.target = self
        popup.action = #selector(changed(_:))
        popup.setAccessibilityLabel(label.stringValue)
        let row = NSStackView(views: [label, NSView(), popup])
        row.spacing = 12
        row.alignment = .centerY
        addArrangedSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        let note = NSTextField(wrappingLabelWithString: chinese
            ? "下次复制时清理旧缓存，不影响截图历史或已保存图片。"
            : "Old cache files are cleared on the next copy. History and saved images are unaffected.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        addArrangedSubview(note)
        note.translatesAutoresizingMaskIntoConstraints = false
        note.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    @objc private func changed(_ sender: NSPopUpButton) {
        guard counts.indices.contains(sender.indexOfSelectedItem) else { return }
        UserDefaults.standard.set(counts[sender.indexOfSelectedItem], forKey: key)
    }
}

@MainActor
final class SnapletSettingsDisclosure: NSStackView {
    private let options: NSStackView

    init(title: String, content: [NSView]) {
        options = NSStackView(views: content)
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 10
        let button = NSButton(title: title, target: self, action: #selector(toggleOptions(_:)))
        button.setButtonType(.pushOnPushOff)
        button.bezelStyle = .inline
        button.font = .systemFont(ofSize: 12)
        button.contentTintColor = SnapletSettingsChrome.accent
        button.setAccessibilityLabel(title)
        addArrangedSubview(button)
        options.orientation = .vertical
        options.alignment = .leading
        options.spacing = 8
        options.isHidden = true
        addArrangedSubview(options)
        options.translatesAutoresizingMaskIntoConstraints = false
        options.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        for view in content {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalTo: options.widthAnchor).isActive = true
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func toggleOptions(_ sender: NSButton) {
        options.isHidden = sender.state != .on
    }
}
