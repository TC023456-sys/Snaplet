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

    static func card(rows: [NSView]) -> NSView {
        let box = SnapletSettingsCard()
        let content = NSStackView(views: rows)
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 9
        content.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: box.topAnchor, constant: 16),
            content.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -16),
            content.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -16),
        ])
        for row in rows {
            row.translatesAutoresizingMaskIntoConstraints = false
            row.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
        return box
    }

    static func toggleRow(_ button: NSButton) -> NSView {
        let label = NSTextField(wrappingLabelWithString: button.title)
        label.font = .systemFont(ofSize: 13)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.setAccessibilityLabel(button.title)
        button.title = ""
        button.setContentHuggingPriority(.required, for: .horizontal)
        let row = NSStackView(views: [label, NSView(), button])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }
}

@MainActor
final class SnapletSettingsCard: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 11, yRadius: 11)
        path.fill()
        NSColor.separatorColor.withAlphaComponent(0.45).setStroke()
        path.lineWidth = 1
        path.stroke()
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
            SnapletSettingsChrome.accent.withAlphaComponent(0.13).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
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
        let row = NSStackView(views: [label, popup])
        row.spacing = 12
        row.alignment = .centerY
        addArrangedSubview(row)
        let note = NSTextField(wrappingLabelWithString: chinese
            ? "默认仅保留最近 1 张；下次复制时自动清理旧缓存，保留当前图片供 Finder 粘贴。不会删除截图历史或已保存的图片。"
            : "Keeps 1 image by default. Old cache files are removed on the next copy; the current Finder image is preserved. History and saved images are unaffected.")
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
