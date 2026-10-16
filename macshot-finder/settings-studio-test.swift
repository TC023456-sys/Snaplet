import AppKit

@MainActor
final class StudioActionProbe: NSObject {
    var received: NSButton?
    @objc func changed(_ sender: NSButton) { received = sender }
}

@main
struct StudioSettingsTest {
    @MainActor static func main() {
        _ = NSApplication.shared
        let probe = StudioActionProbe()
        let button = NSButton(checkboxWithTitle: "Launch at login", target: probe, action: #selector(StudioActionProbe.changed(_:)))
        button.state = .on
        let row = SnapletSettingsChrome.toggleRow(button)
        precondition(button.state == .on)
        precondition(button.target === probe)
        precondition(button.action == #selector(StudioActionProbe.changed(_:)))
        precondition(button.cell is SnapletSwitchCell)
        precondition(button.isDescendant(of: row))
        button.performClick(nil)
        precondition(probe.received === button)
        precondition(button.state == .off)

        let disabled = NSButton(checkboxWithTitle: "Disabled", target: nil, action: nil)
        disabled.isEnabled = false
        _ = SnapletSettingsChrome.toggleRow(disabled)
        precondition(!disabled.isEnabled)
        let group = SnapletSettingsChrome.card(rows: [row])
        precondition(row.isDescendant(of: group))
        let option = NSButton(title: "Existing action", target: probe, action: #selector(StudioActionProbe.changed(_:)))
        let disclosure = SnapletSettingsDisclosure(title: "Advanced", content: [option])
        precondition(option.isDescendant(of: disclosure))
        precondition(option.target === probe)
        print("PASS: native toggle target/action, state, disabled state, group ownership and advanced actions preserved")
    }
}
