import Cocoa
import Carbon
import ApplicationServices

/// Owns only its own hotkey and panel. Capture hotkeys and capture windows are untouched.
@MainActor
final class WindowSwitcher: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    static let shared = WindowSwitcher()
    var canPresent: () -> Bool = { true }
    private var hotkey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var panel: NSPanel?
    private let search = NSSearchField()
    private let table = NSTableView()
    private let status = NSTextField(labelWithString: "")
    private var entries: [WindowEntry] = []
    private var filtered: [WindowEntry] = []
    private var monitor: Any?
    private var previousApp: NSRunningApplication?
    private var loading = false
    private var generation = 0
    private var followsOption = false

    private struct WindowEntry {
        let app: NSRunningApplication
        let element: AXUIElement
        let title: String
        let minimized: Bool
    }

    func start() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ in
            guard let event = event else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard identifier.signature == 0x5357_4954 else { return OSStatus(eventNotHandledErr) }
            DispatchQueue.main.async { WindowSwitcher.shared.present(fromKeyboard: true) }
            return noErr
        }, 1, &spec, nil, &handler)
        guard installed == noErr else { return }
        let id = EventHotKeyID(signature: 0x5357_4954, id: 1001)
        let result = RegisterEventHotKey(UInt32(kVK_Tab), UInt32(optionKey), id, GetEventDispatcherTarget(), 0, &hotkey)
        if result != noErr { status.stringValue = "⌥Tab 已被其他软件占用，请先退出 AltTab。" }
    }

    func appendMenu(to menu: NSMenu) {
        let item = NSMenuItem(title: "窗口切换…", action: #selector(openFromMenu), keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: nil)
        item.toolTip = "按 ⌥Tab 切换窗口；支持输入标题搜索。"
        menu.addItem(item)
    }

    @objc private func openFromMenu() { present(fromKeyboard: false) }

    func cancelForCapture() {
        if loading || panel?.isVisible == true { dismiss(restoreFocus: true) }
    }

    func present(fromKeyboard: Bool) {
        guard canPresent() else { return }
        if panel?.isVisible == true {
            if fromKeyboard { moveSelection(1) }
            return
        }
        guard !loading else { return }
        guard AXIsProcessTrusted() else {
            let alert = NSAlert()
            alert.messageText = "窗口切换需要辅助功能权限"
            alert.informativeText = "请在系统设置 → 隐私与安全性 → 辅助功能中允许 Snaplet。截图功能不受此权限影响。"
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "取消")
            if alert.runModal() == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
            return
        }
        previousApp = NSWorkspace.shared.frontmostApplication
        followsOption = fromKeyboard
        generation += 1
        let request = generation
        loading = true
        let applications = NSWorkspace.shared.runningApplications.filter {
            $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && $0.activationPolicy == .regular
        }
        // AX queries may block on another app; keep them off the screenshot and UI thread.
        DispatchQueue.global(qos: .userInitiated).async {
            let windows = Self.readWindows(applications)
            DispatchQueue.main.async {
                guard self.generation == request else { return }
                self.loading = false
                guard self.canPresent() else { return }
                self.entries = windows
                self.showPanel()
            }
        }
    }

    nonisolated private static func readWindows(_ apps: [NSRunningApplication]) -> [WindowEntry] {
        let cgWindows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var ranks: [String: Int] = [:]
        for (index, window) in cgWindows.enumerated() {
            if let pid = window[kCGWindowOwnerPID as String] as? Int, let title = window[kCGWindowName as String] as? String {
                let key = "\(pid):\(title)"
                if ranks[key] == nil { ranks[key] = index }
            }
        }
        var result: [WindowEntry] = []
        for app in apps {
            let root = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(root, 0.25)
            var raw: CFTypeRef?
            guard AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &raw) == .success,
                  let windows = raw as? [AXUIElement] else { continue }
            for window in windows {
                AXUIElementSetMessagingTimeout(window, 0.25)
                var role: CFTypeRef?
                AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &role)
                guard (role as? String) == kAXStandardWindowSubrole || (role as? String) == kAXDialogSubrole else { continue }
                var title: CFTypeRef?
                var minimized: CFTypeRef?
                AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title)
                AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimized)
                result.append(WindowEntry(app: app, element: window,
                                          title: (title as? String).flatMap { $0.isEmpty ? nil : $0 } ?? app.localizedName ?? "未命名窗口",
                                          minimized: (minimized as? Bool) ?? false))
            }
        }
        return result.enumerated().sorted { lhs, rhs in
            let a = ranks["\(lhs.element.app.processIdentifier):\(lhs.element.title)"] ?? (100000 + lhs.offset)
            let b = ranks["\(rhs.element.app.processIdentifier):\(rhs.element.title)"] ?? (100000 + rhs.offset)
            return a < b
        }.map(\.element)
    }

    private func showPanel() {
        if panel == nil { buildPanel() }
        guard let panel = panel else { return }
        search.stringValue = ""
        filtered = entries
        table.reloadData()
        let previousPID = previousApp?.processIdentifier
        let initial = followsOption && filtered.count > 1 && filtered.first?.app.processIdentifier == previousPID ? 1 : 0
        if !filtered.isEmpty { table.selectRowIndexes(IndexSet(integer: initial), byExtendingSelection: false) }
        updateStatus()
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(search)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self = self else { return event }
            if event.type == .flagsChanged && self.followsOption && !event.modifierFlags.contains(.option) {
                self.commitSelection()
                return event
            }
            if event.type == .keyDown {
                switch event.keyCode {
                case 53: self.dismiss(restoreFocus: true); return nil
                case 36, 76: self.commitSelection(); return nil
                case 48: self.moveSelection(event.modifierFlags.contains(.shift) ? -1 : 1); return nil
                case 125: self.moveSelection(1); return nil
                case 126: self.moveSelection(-1); return nil
                default: break
                }
            }
            return event
        }
        if followsOption && !NSEvent.modifierFlags.contains(.option) { commitSelection() }
    }

    private func buildPanel() {
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 680, height: 480),
                             styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Snaplet · 窗口切换"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        let content = NSView()
        window.contentView = content
        search.placeholderString = "搜索窗口标题或应用名称"
        search.delegate = self
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("window"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 52
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(commitSelection)
        table.allowsEmptySelection = false
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        for view in [search, scroll, status] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            search.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            search.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scroll.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -10),
            status.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            status.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            status.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12)
        ])
        panel = window
    }

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = filtered[row]
        let cell = NSTableCellView()
        let icon = NSImageView()
        icon.image = entry.app.icon
        icon.translatesAutoresizingMaskIntoConstraints = false
        let text = NSTextField(labelWithString: "\(entry.title)\n\(entry.app.localizedName ?? "")\(entry.minimized ? " · 已最小化" : "")")
        text.lineBreakMode = .byTruncatingTail
        text.font = .systemFont(ofSize: 13)
        text.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(icon)
        cell.addSubview(text)
        cell.textField = text
        cell.imageView = icon
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 32), icon.heightAnchor.constraint(equalToConstant: 32),
            text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    func controlTextDidChange(_ obj: Notification) {
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        filtered = entries.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || ($0.app.localizedName ?? "").localizedCaseInsensitiveContains(query) }
        table.reloadData()
        if !filtered.isEmpty { table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
        updateStatus()
    }

    private func updateStatus() {
        status.stringValue = filtered.isEmpty ? "没有匹配的窗口" : "\(filtered.count) 个窗口 · ↑↓ / Tab 选择 · 回车或双击切换 · Esc 取消"
    }

    private func moveSelection(_ offset: Int) {
        guard !filtered.isEmpty else { return }
        let row = (max(table.selectedRow, 0) + offset + filtered.count) % filtered.count
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    @objc private func commitSelection() {
        let row = table.selectedRow
        guard filtered.indices.contains(row) else { dismiss(restoreFocus: true); return }
        let chosen = filtered[row]
        dismiss(restoreFocus: false)
        DispatchQueue.global(qos: .userInitiated).async {
            if chosen.minimized { AXUIElementSetAttributeValue(chosen.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse) }
            chosen.app.activate(options: [.activateIgnoringOtherApps])
            AXUIElementPerformAction(chosen.element, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(chosen.element, kAXMainAttribute as CFString, kCFBooleanTrue)
            DispatchQueue.main.async { self.entries.removeAll(); self.filtered.removeAll() }
        }
    }

    private func dismiss(restoreFocus: Bool) {
        generation += 1
        loading = false
        if let monitor = monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        panel?.orderOut(nil)
        if restoreFocus { previousApp?.activate(options: [.activateIgnoringOtherApps]) }
    }
}
