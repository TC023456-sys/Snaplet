import AppKit

// Isolated UI construction test. Never requests screen access or opens settings.
func L(_ text: String) -> String { text }

@main
struct PermissionLayoutTest {
    @MainActor static func main() {
        _ = NSApplication.shared
        let controller = PermissionOnboardingController()
        guard let content = controller.window?.contentView else { fatalError("No content view") }
        content.layoutSubtreeIfNeeded()
        let buttons = content.subviews.compactMap { $0 as? NSButton }
        let open = buttons.first { $0.title == "Open Screen Recording Settings" }!
        let next = buttons.first { $0.title == "Continue" }!
        precondition(!open.isHidden && !next.isHidden)
        precondition(!open.frame.intersects(next.frame))
        precondition(open.frame.minX >= 20 && next.frame.maxX <= content.bounds.maxX - 20)
        for button in buttons {
            let width = (button.title as NSString).size(withAttributes: [.font: button.font!]).width
            precondition(width <= button.bounds.width - 16, "Button title would be clipped")
        }
        precondition(open.keyEquivalent.isEmpty && next.keyEquivalent == "\r")
        precondition(buttons.filter { !$0.isHidden && $0.keyEquivalent == "\r" }.count == 1)
        precondition(open.target === controller && next.target === controller)
        precondition(open.action != nil && next.action != nil && open.action != next.action)
        print("PASS: permission buttons visible, separated and bounded; only Continue owns Return; actions preserved")
    }
}
