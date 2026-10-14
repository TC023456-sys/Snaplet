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
        super.draw(dirtyRect)
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
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
