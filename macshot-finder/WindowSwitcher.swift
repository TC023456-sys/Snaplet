import Cocoa
import Carbon
import ApplicationServices
import ScreenCaptureKit

/// Owns only its own hotkey and panel. Capture hotkeys and capture windows are untouched.
@MainActor
final class WindowSwitcher: NSObject {
    static let shared = WindowSwitcher()
    var canPresent: () -> Bool = { true }
    var isPresenting: Bool { loading || presentationWork != nil || panel?.isVisible == true }
    private var systemShortcutTap: WindowSwitcherSystemHotkeyTap?
    private var availabilityTimer: Timer?
    private var presentationWork: DispatchWorkItem?
    private var cachedEntries: [WindowEntry] = []
    private var closingWindows: Set<CGWindowID> = []
    private var cacheDate = Date.distantPast
    private var cacheRefreshing = false
    private var snapshotCompletions: [([WindowEntry]) -> Void] = []
    private var windowCacheRevision = 0
    private var cachedWindowRevision = -1
    private var input = WindowSwitchKeystrokes()
    private var hotkey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var panel: NSPanel?
    private let scroll = NSScrollView()
    private let grid = WindowThumbnailGrid()
    private var cards: [WindowThumbnailCard] = []
    private var selectedIndex = 0
    private var columns = 4
    private var previewCache: [CGWindowID: NSImage] = [:]
    private var previewTask: Task<Void, Never>?
    private var gestureStartedAt = ProcessInfo.processInfo.systemUptime
    private var previewDates: [CGWindowID: Date] = [:]
    private var cardCache: [CGWindowID: (fingerprint: String, card: WindowThumbnailCard)] = [:]
    private var iconCache: [pid_t: NSImage] = [:]
    private var entries: [WindowEntry] = []
    private var filtered: [WindowEntry] = []
    private var monitor: Any?
    private var outsideClickMonitor: Any?
    private var previousApp: NSRunningApplication?
    private var switchOrder = WindowSwitchOrder()
    private var currentWindowID: CGWindowID?
    private var lastPointerLocation = NSPoint.zero
    private var focusTransitionWindowID: CGWindowID?
    private let focusQueue = DispatchQueue(label: "Snaplet.windowFocus", qos: .userInteractive)
    private var focusTransitionGeneration: Int?
    private var focusObservers: [pid_t: AXObserver] = [:]
    private var workspaceObservers: [NSObjectProtocol] = []
    private var loading = false
    private var isDismissing = false
    private var generation = 0
    private var closeReleaseModifiers: NSEvent.ModifierFlags = []
    private var followsOption = false
    private var heldModifiers: NSEvent.ModifierFlags = .option
    private(set) var shortcutError: String?

    private struct WindowEntry {
        let app: NSRunningApplication
        let element: AXUIElement
        let windowID: CGWindowID
        let title: String
        let minimized: Bool
    }

    func start() {
        if workspaceObservers.isEmpty { startFocusTracking() }
        if handler != nil { resumeShortcut(); return }
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
        resumeShortcut()
        refreshWindowCache()
        // Build the invisible view tree ahead of the first held shortcut.
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.panel == nil else { return }
            self.buildPanel()
        }
    }

    private func startFocusTracking() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didLaunchApplicationNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self = self,
                      let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self.updateRemoteShortcutAvailability()
                self.observeFocus(in: app)
                if !self.isPresenting, self.focusTransitionGeneration == nil, app.isActive { _ = self.noteFocusedWindow(in: app) }
            })
        }
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let self = self, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let observer = self.focusObservers.removeValue(forKey: app.processIdentifier) else { return }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        })
        for app in NSWorkspace.shared.runningApplications { observeFocus(in: app) }
        if let app = NSWorkspace.shared.frontmostApplication { _ = noteFocusedWindow(in: app) }
    }

    private func observeFocus(in app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard pid != ProcessInfo.processInfo.processIdentifier, app.activationPolicy == .regular,
              focusObservers[pid] == nil else { return }
        var observer: AXObserver?
        let result = AXObserverCreate(pid, { _, element, notification, _ in
            var pid: pid_t = 0
            guard AXUIElementGetPid(element, &pid) == .success else { return }
            let processID = pid
            DispatchQueue.main.async {
                let owner = WindowSwitcher.shared
                if notification as String == kAXWindowCreatedNotification {
                    owner.windowCacheRevision += 1
                    owner.cacheDate = .distantPast
                    owner.refreshWindowCache()
                }
                guard !owner.isPresenting, owner.focusTransitionGeneration == nil, let app = NSWorkspace.shared.frontmostApplication,
                      app.processIdentifier == processID else { return }
                _ = owner.noteFocusedWindow(in: app)
            }
        }, &observer)
        guard result == .success, let observer = observer else { return }
        let root = AXUIElementCreateApplication(pid)
        let focused = AXObserverAddNotification(observer, root, kAXFocusedWindowChangedNotification as CFString, nil)
        let main = AXObserverAddNotification(observer, root, kAXMainWindowChangedNotification as CFString, nil)
        let created = AXObserverAddNotification(observer, root, kAXWindowCreatedNotification as CFString, nil)
        guard focused == .success || main == .success || created == .success else { return }
        focusObservers[pid] = observer
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }

    @discardableResult
    private func noteFocusedWindow(in app: NSRunningApplication) -> CGWindowID? {
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.08)
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(root, kAXFocusedWindowAttribute as CFString, &raw) == .success,
              let raw = raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        let window = raw as! AXUIElement
        var id: CGWindowID = 0
        guard windowSwitcherGetWindowID(window, &id) == .success, id != 0 else { return nil }
        if !cachedEntries.contains(where: { $0.windowID == id }) {
            windowCacheRevision += 1
            cacheDate = .distantPast
        }
        switchOrder.noteFocus(id)
        return id
    }

    var shortcut: (keyCode: UInt32, modifiers: UInt32) {
        let defaults = UserDefaults.standard
        return (UInt32(defaults.object(forKey: "windowSwitcherKeyCode") as? Int ?? kVK_Tab),
                UInt32(defaults.object(forKey: "windowSwitcherModifiers") as? Int ?? optionKey))
    }

    var shortcutDisplay: String {
        let modifiers = HotkeyManager.modifierString(from: shortcut.modifiers).map { String($0) }.joined(separator: "+")
        return (modifiers.isEmpty ? "" : modifiers + "+") + HotkeyManager.keyString(from: shortcut.keyCode)
    }

    func suspendShortcut() {
        systemShortcutTap?.stop()
        systemShortcutTap = nil
        availabilityTimer?.invalidate()
        availabilityTimer = nil
        if let hotkey = hotkey { UnregisterEventHotKey(hotkey) }
        hotkey = nil
    }

    private var remoteAppIsFrontmost: Bool {
        WindowSwitchRemotePolicy.isRemoteApplication(bundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }

    private func updateRemoteShortcutAvailability() {
        if remoteAppIsFrontmost {
            if let hotkey = hotkey { UnregisterEventHotKey(hotkey); self.hotkey = nil }
        } else if handler != nil {
            resumeShortcut()
        }
    }

    func resumeShortcut() {
        guard !remoteAppIsFrontmost else { return }
        guard hotkey == nil, systemShortcutTap == nil, handler != nil else { return }
        if shortcut.keyCode == UInt32(kVK_Tab), shortcut.modifiers == UInt32(cmdKey) {
            shortcutError = installSystemShortcutTap() ? nil : "无法接管 ⌘+Tab，请刷新辅助功能授权后重启 Snaplet。"
            return
        }
        var reference: EventHotKeyRef?
        let result = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers,
            EventHotKeyID(signature: 0x5357_4954, id: 1001), GetEventDispatcherTarget(), 0, &reference)
        hotkey = result == noErr ? reference : nil
        shortcutError = result == noErr ? nil : "快捷键被其他应用或系统占用，请换一个组合。"
    }

    // Command-Tab is handled by the Dock before ordinary Carbon hotkeys.
    // Consume only this exact chord (plus Shift for backwards cycling), never other typing.
    private func installSystemShortcutTap() -> Bool {
        let bridge = WindowSwitcherSystemHotkeyTap(onPress: { step in
            DispatchQueue.main.async { WindowSwitcher.shared.present(fromKeyboard: true, step: step) }
        }, onRelease: {
            DispatchQueue.main.async { WindowSwitcher.shared.releaseKeyboardShortcut() }
        })
        guard bridge.start() else { return false }
        bridge.setEnabled(canPresent())
        systemShortcutTap = bridge
        availabilityTimer?.invalidate()
        availabilityTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self else { return }
                self.systemShortcutTap?.setEnabled(self.canPresent())
            }
        }
        return true
    }

    private func traceSwitch(_ message: String) {
        DispatchQueue.global(qos: .utility).async { CaptureDiagnostics.record("switcher " + message) }
    }

    func refreshShortcutAvailability() {
        systemShortcutTap?.setEnabled(canPresent())
    }

    private func releaseKeyboardShortcut() {
        traceSwitch("release presenting=\(isPresenting) loading=\(loading)")
        if !closeReleaseModifiers.isEmpty {
            dismiss(restoreFocus: true)
            return
        }
        guard followsOption, isPresenting else { return }
        input.release()
        if !loading && !filtered.isEmpty { commitSelection() }
    }

    private func refreshWindowCache() {
        guard !cacheRefreshing, AXIsProcessTrusted(),
              cachedEntries.isEmpty || cachedWindowRevision != windowCacheRevision || Date().timeIntervalSince(cacheDate) >= 1 else { return }
        requestWindowSnapshot()
    }

    // Background warming and shortcut presentation share one AX read. Only
    // this path publishes the cache, so a slower old scan cannot overwrite a
    // newer result or double the load on another application's AX server.
    private func requestWindowSnapshot(completion: (([WindowEntry]) -> Void)? = nil) {
        if let completion = completion { snapshotCompletions.append(completion) }
        guard !cacheRefreshing else { return }
        beginWindowSnapshotRead()
    }

    private func beginWindowSnapshotRead() {
        cacheRefreshing = true
        let revision = windowCacheRevision
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && $0.activationPolicy == .regular
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let windows = Self.readWindows(apps)
            DispatchQueue.main.async {
                self.cacheRefreshing = false
                guard self.windowCacheRevision == revision else {
                    self.beginWindowSnapshotRead()
                    return
                }
                self.cachedEntries = windows
                self.cachedWindowRevision = revision
                self.cacheDate = Date()
                let completions = self.snapshotCompletions
                self.snapshotCompletions.removeAll(keepingCapacity: true)
                for completion in completions { completion(windows) }
            }
        }
    }

    private func preparePresentation(_ windows: [WindowEntry], request: Int) {
        guard generation == request else { return }
        guard canPresent() else { dismiss(restoreFocus: false); return }
        loading = false
        let available = windows.map(\.windowID)
        if currentWindowID == nil, let app = previousApp,
           app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            currentWindowID = windows.first(where: { $0.app.processIdentifier == app.processIdentifier && !$0.minimized })?.windowID
        }
        var ids = switchOrder.snapshot(available: available, current: currentWindowID)
        for steps in input.completed {
            guard !ids.isEmpty else { break }
            let index = WindowSwitchOrder.initialIndex(in: ids, current: currentWindowID, keyboard: true, step: steps)
            currentWindowID = ids[index]
            switchOrder.noteFocus(ids[index])
            ids = switchOrder.snapshot(available: available, current: currentWindowID)
        }
        let byID = Dictionary(windows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
        entries = ids.compactMap { byID[$0] }
        filtered = entries
        selectedIndex = WindowSwitchOrder.initialIndex(in: ids, current: currentWindowID,
            keyboard: followsOption, step: input.initialStep, queued: input.extraSteps)
        traceSwitch("ready generation=\(generation) windows=\(ids.count) current=\(currentWindowID ?? 0) selected=\(selectedIndex) released=\(input.released)")
        // Quick taps commit without activating/drawing the switcher at all.
        if followsOption && (input.released || !NSEvent.modifierFlags.isSuperset(of: heldModifiers)) {
            commitSelection()
            return
        }
        if !followsOption { showPanel(); return }
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.generation == request else { return }
            self.presentationWork = nil
            if self.input.released { self.commitSelection() } else { self.showPanel() }
        }
        presentationWork = work
        let remaining = max(0, 0.055 - (ProcessInfo.processInfo.systemUptime - gestureStartedAt))
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining, execute: work)
    }

    /// Persist only after registration succeeds; a rejected shortcut never replaces the working one.
    @discardableResult
    func setShortcut(keyCode: UInt32, modifiers: UInt32) -> String? {
        for slot in HotkeyManager.HotkeySlot.allCases {
            let value = HotkeyManager.readHotkey(for: slot)
            if (value.modifiers != 0 || HotkeyManager.isFunctionKey(value.keyCode)) && value.keyCode == keyCode && value.modifiers == modifiers {
                return "与“\(slot.label)”快捷键冲突，请换一个组合。"
            }
        }
        if shortcut.keyCode == keyCode && shortcut.modifiers == modifiers && (hotkey != nil || systemShortcutTap != nil) { return nil }
        if keyCode == UInt32(kVK_Tab), modifiers == UInt32(cmdKey) {
            if systemShortcutTap == nil && !installSystemShortcutTap() { return "无法接管 ⌘+Tab，请检查辅助功能权限，原设置已保留。" }
            if let hotkey = hotkey { UnregisterEventHotKey(hotkey) }
            hotkey = nil
            UserDefaults.standard.set(Int(keyCode), forKey: "windowSwitcherKeyCode")
            UserDefaults.standard.set(Int(modifiers), forKey: "windowSwitcherModifiers")
            shortcutError = nil
            return nil
        }
        var reference: EventHotKeyRef?
        let result = RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: 0x5357_4954, id: 1001),
                                         GetEventDispatcherTarget(), 0, &reference)
        guard result == noErr, let reference = reference else {
            return "快捷键被其他应用或系统占用，原设置已保留。"
        }
        suspendShortcut()
        hotkey = reference
        UserDefaults.standard.set(Int(keyCode), forKey: "windowSwitcherKeyCode")
        UserDefaults.standard.set(Int(modifiers), forKey: "windowSwitcherModifiers")
        shortcutError = nil
        return nil
    }

    func appendMenu(to menu: NSMenu) {
        let item = NSMenuItem(title: "窗口切换…", action: #selector(openFromMenu), keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: nil)
        item.toolTip = "切换窗口；快捷键可在设置 → 窗口切换中修改。"
        menu.addItem(item)
    }

    @objc private func openFromMenu() { present(fromKeyboard: false) }

    func cancelForCapture() {
        // Always remove monitors, including those left behind after a hidden panel.
        systemShortcutTap?.setEnabled(false)
        dismiss(restoreFocus: false)
    }

    func present(fromKeyboard: Bool, step: Int = 1) {
        traceSwitch("press keyboard=\(fromKeyboard) allowed=\(canPresent()) loading=\(loading)")
        guard canPresent(), !remoteAppIsFrontmost else { return }
        if panel?.isVisible == true {
            if fromKeyboard { followsOption = true; moveSelection(step) }
            return
        }
        if loading || presentationWork != nil {
            if fromKeyboard {
                input.press(step: step)
                if !loading {
                    selectedIndex = WindowSwitchOrder.initialIndex(in: filtered.map(\.windowID), current: currentWindowID,
                        keyboard: true, step: input.initialStep, queued: input.extraSteps)
                }
            }
            return
        }
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
        gestureStartedAt = ProcessInfo.processInfo.systemUptime
        previousApp = NSWorkspace.shared.frontmostApplication
        currentWindowID = focusTransitionGeneration != nil
            ? focusTransitionWindowID
            : previousApp.flatMap { noteFocusedWindow(in: $0) }
        input.begin(step: step)
        followsOption = fromKeyboard
        heldModifiers = []
        if shortcut.modifiers & UInt32(cmdKey) != 0 { heldModifiers.insert(.command) }
        if shortcut.modifiers & UInt32(optionKey) != 0 { heldModifiers.insert(.option) }
        if shortcut.modifiers & UInt32(controlKey) != 0 { heldModifiers.insert(.control) }
        if shortcut.modifiers & UInt32(shiftKey) != 0 { heldModifiers.insert(.shift) }
        generation += 1
        let request = generation
        loading = true
        if !cachedEntries.isEmpty && cachedWindowRevision == windowCacheRevision {
            // Keep the last snapshot warm after idle. A cheap WindowServer ID
            // check removes closed windows; expensive AX refresh stays off-thread.
            let info = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
            let live = Set(info.compactMap { $0[kCGWindowNumber as String] as? UInt32 })
            let known = Set(cachedEntries.map(\.windowID))
            // Some apps do not emit AXWindowCreated. Detect a new normal-sized
            // window in the source app before displaying an obsolete snapshot.
            let sourceHasNewWindow = info.contains { window in
                guard let pid = previousApp?.processIdentifier,
                      (window[kCGWindowOwnerPID as String] as? Int) == Int(pid),
                      (window[kCGWindowLayer as String] as? Int ?? 0) == 0,
                      let id = window[kCGWindowNumber as String] as? UInt32,
                      !known.contains(id),
                      let bounds = window[kCGWindowBounds as String] as? [String: Any],
                      let width = bounds["Width"] as? Double,
                      let height = bounds["Height"] as? Double else { return false }
                return width >= 100 && height >= 70
            }
            if currentWindowID == nil, let app = previousApp,
               app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                currentWindowID = info.first(where: {
                    ($0[kCGWindowOwnerPID as String] as? Int) == Int(app.processIdentifier)
                    && ($0[kCGWindowLayer as String] as? Int ?? 0) == 0
                    && known.contains($0[kCGWindowNumber as String] as? UInt32 ?? 0)
                })?[kCGWindowNumber as String] as? UInt32
                if let current = currentWindowID { switchOrder.noteFocus(current) }
            }
            let cached = cachedEntries.filter { !$0.app.isTerminated && live.contains($0.windowID) }
            if !sourceHasNewWindow && !cached.isEmpty && (currentWindowID == nil || cached.contains(where: { $0.windowID == currentWindowID })) {
                preparePresentation(cached, request: request)
                refreshWindowCache()
                return
            }
        }
        loadWindowSnapshot(request: request)
    }

    private func loadWindowSnapshot(request: Int) {
        requestWindowSnapshot { [weak self] windows in
            guard let self = self, self.generation == request else { return }
            self.preparePresentation(windows, request: request)
        }
    }

    nonisolated private static func readWindows(_ apps: [NSRunningApplication]) -> [WindowEntry] {
        let cg = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var ranks: [CGWindowID: Int] = [:]
        var details: [CGWindowID: [String: Any]] = [:]
        for (index, window) in cg.enumerated() {
            if let id = window[kCGWindowNumber as String] as? UInt32 { ranks[id] = index; details[id] = window }
        }
        var result: [WindowEntry] = []
        for app in apps {
            let root = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(root, 0.2)
            var raw: CFTypeRef?
            guard AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &raw) == .success,
                  let windows = raw as? [AXUIElement] else { continue }
            for window in windows {
                AXUIElementSetMessagingTimeout(window, 0.2)
                var role: CFTypeRef?
                AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &role)
                guard (role as? String) == kAXStandardWindowSubrole || (role as? String) == kAXDialogSubrole else { continue }
                var id: CGWindowID = 0
                guard windowSwitcherGetWindowID(window, &id) == .success, id != 0 else { continue }
                if let info = details[id] {
                    if (info[kCGWindowLayer as String] as? Int ?? 0) != 0 { continue }
                    if let bounds = info[kCGWindowBounds as String] as? [String: Any],
                       let width = bounds["Width"] as? Double, let height = bounds["Height"] as? Double,
                       width < 100 || height < 70 { continue }
                }
                var title: CFTypeRef?
                var minimized: CFTypeRef?
                AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title)
                AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimized)
                let name = (title as? String).flatMap { $0.isEmpty ? nil : $0 } ?? app.localizedName ?? "未命名窗口"
                if app.bundleIdentifier == "com.apple.finder" && details[id] == nil { continue }
                result.append(WindowEntry(app: app, element: window, windowID: id, title: name, minimized: (minimized as? Bool) ?? false))
            }
        }
        return result.enumerated().sorted {
            (ranks[$0.element.windowID] ?? (100000 + $0.offset)) < (ranks[$1.element.windowID] ?? (100000 + $1.offset))
        }.map(\.element)
    }

    private func showPanel() {
        if panel == nil { buildPanel() }
        guard let panel = panel else { return }
        filtered = entries
        selectedIndex = WindowSwitchOrder.initialIndex(in: filtered.map(\.windowID), current: currentWindowID,
            keyboard: followsOption, step: input.initialStep, queued: input.extraSteps)
        lastPointerLocation = NSEvent.mouseLocation
        renderGrid()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(nil)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .leftMouseDown]) { [weak self] event in
            guard let self = self, self.panel?.isVisible == true, self.canPresent() else { return event }
            if event.type == .leftMouseDown, let panel = self.panel {
                let screenPoint = event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
                if panel.frame.contains(screenPoint) {
                    let panelPoint = panel.convertPoint(fromScreen: screenPoint)
                    // Resolve the card before AppKit can activate another window or
                    // forward mouse-down through the thumbnail's image/label views.
                    if let card = self.cards.first(where: { $0.bounds.contains($0.convert(panelPoint, from: nil)) }) {
                        let local = card.convert(panelPoint, from: nil)
                        if card.isClosePoint(local) {
                            self.beginCloseInteraction(modifiers: event.modifierFlags)
                            return event
                        }
                        card.onActivate?()
                        return nil
                    }
                } else {
                    self.dismiss(restoreFocus: false)
                    return event
                }
            }
            if event.type == .flagsChanged && !self.closeReleaseModifiers.isEmpty
                && !event.modifierFlags.isSuperset(of: self.closeReleaseModifiers) {
                self.dismiss(restoreFocus: true)
                return event
            }
            if event.type == .flagsChanged && self.followsOption && !event.modifierFlags.isSuperset(of: self.heldModifiers) {
                self.commitSelection()
                return event
            }
            if event.type == .keyDown {
                switch event.keyCode {
                case 53: self.dismiss(restoreFocus: true); return nil
                case 36, 76: self.commitSelection(); return nil
                case 48: self.moveSelection(event.modifierFlags.contains(.shift) ? -1 : 1); return nil
                case 124: self.moveSelection(1); return nil
                case 123: self.moveSelection(-1); return nil
                case 125: self.moveSelection(self.columns); return nil
                case 126: self.moveSelection(-self.columns); return nil
                default: break
                }
            }
            return event
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            DispatchQueue.main.async { self?.dismiss(restoreFocus: false) }
        }
        traceSwitch("panel shown elapsedMs=\(Int((ProcessInfo.processInfo.systemUptime - gestureStartedAt) * 1000)) cards=\(cards.count)")
        loadPreviews()
        if followsOption && !NSEvent.modifierFlags.isSuperset(of: heldModifiers) { commitSelection() }
    }

    private func buildPanel() {
        let window = WindowSwitcherPanel(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 650),
                                         styleMask: [.borderless], backing: .buffered, defer: false)
        window.title = "Snaplet · 窗口预览"
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = false
        window.acceptsMouseMovedEvents = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.animationBehavior = .none
        window.appearance = nil
        let content = WindowSwitcherGlassView()
        window.contentView = content
        scroll.documentView = grid
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18)
        ])
        panel = window
    }

    private func renderGrid() {
        guard let panel = panel else { return }
        cards.removeAll()
        grid.subviews.forEach { $0.removeFromSuperview() }
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        let available = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        columns = max(1, min(4, max(filtered.count, 1), Int((available.width - 100) / 256)))
        let tileWidth: CGFloat = 240
        let tileHeight: CGFloat = 190
        let gap: CGFloat = 12
        let rows = max(1, Int(ceil(Double(filtered.count) / Double(columns))))
        let width = CGFloat(columns) * tileWidth + CGFloat(columns - 1) * gap + 36
        let gridHeight = CGFloat(rows) * tileHeight + CGFloat(rows - 1) * gap
        let height = min(available.height - 100, gridHeight + 36)
        let rect = NSRect(x: available.midX - width / 2, y: available.midY - height / 2, width: width, height: height)
        panel.setFrame(rect, display: false)
        grid.frame = NSRect(x: 0, y: 0, width: width - 36, height: gridHeight)
        for (index, entry) in filtered.enumerated() {
            let appName = entry.app.localizedName ?? ""
            let fingerprint = entry.title + "|" + appName + "|" + String(entry.minimized)
            let card: WindowThumbnailCard
            if let cached = cardCache[entry.windowID], cached.fingerprint == fingerprint {
                card = cached.card
                if let image = previewCache[entry.windowID] { card.setPreview(image) }
            } else {
                let pid = entry.app.processIdentifier
                if iconCache[pid] == nil { iconCache[pid] = entry.app.icon }
                card = WindowThumbnailCard(title: entry.title, appName: appName, icon: iconCache[pid],
                    minimized: entry.minimized, image: previewCache[entry.windowID])
                cardCache[entry.windowID] = (fingerprint, card)
            }
            card.frame = NSRect(x: CGFloat(index % columns) * (tileWidth + gap), y: CGFloat(index / columns) * (tileHeight + gap), width: tileWidth, height: tileHeight)
            card.onActivate = { [weak self] in self?.selectedIndex = index; self?.commitSelection() }
            card.onClose = { [weak self] in self?.closeWindowNatively(id: entry.windowID) }
            card.onHover = { [weak self] in
                guard let self = self else { return }
                let point = NSEvent.mouseLocation
                guard hypot(point.x - self.lastPointerLocation.x, point.y - self.lastPointerLocation.y) > 1 else { return }
                self.lastPointerLocation = point
                guard self.selectedIndex != index else { return }
                self.selectedIndex = index
                self.updateSelection(scrollIntoView: false)
            }
            grid.addSubview(card)
            cards.append(card)
        }
        if filtered.isEmpty {
            let empty = NSTextField(labelWithString: "没有可切换的窗口")
            empty.textColor = .secondaryLabelColor
            empty.frame = NSRect(x: 20, y: 70, width: 300, height: 24)
            grid.addSubview(empty)
        }
        let live = Set(filtered.map(\.windowID))
        cardCache = cardCache.filter { live.contains($0.key) }
        previewCache = previewCache.filter { live.contains($0.key) }
        previewDates = previewDates.filter { live.contains($0.key) }
        updateSelection()
    }

    private func loadPreviews() {
        previewTask?.cancel()
        let request = generation
        let visible = scroll.documentVisibleRect
        let visibleIDs = Set(cards.enumerated().filter { $0.element.frame.intersects(visible) }.map { filtered[$0.offset].windowID })
        let selectedID = filtered.indices.contains(selectedIndex) ? filtered[selectedIndex].windowID : 0
        let now = Date()
        let windows = entries.enumerated().filter {
            previewCache[$0.element.windowID] == nil || now.timeIntervalSince(previewDates[$0.element.windowID] ?? .distantPast) >= 2
        }.sorted {
            let left = $0.element.windowID == selectedID ? 0 : (visibleIDs.contains($0.element.windowID) ? 1 : 2)
            let right = $1.element.windowID == selectedID ? 0 : (visibleIDs.contains($1.element.windowID) ? 1 : 2)
            return (left, $0.offset) < (right, $1.offset)
        }.map(\.element)
        guard !windows.isEmpty else { return }
        previewTask = Task { [weak self] in
            guard let self = self else { return }
            guard #available(macOS 14.0, *), !Task.isCancelled, self.generation == request else { return }
            do {
                try await Task.sleep(nanoseconds: 20_000_000)
                guard !Task.isCancelled, self.generation == request, self.panel?.isVisible == true else { return }
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
                for entry in windows {
                    guard !Task.isCancelled, self.generation == request, self.panel?.isVisible == true else { return }
                    guard let window = content.windows.first(where: { $0.windowID == entry.windowID }), window.frame.width > 0, window.frame.height > 0 else { continue }
                    let scale = min(440 / window.frame.width, 240 / window.frame.height)
                    let config = SCStreamConfiguration()
                    config.width = max(1, Int(window.frame.width * scale))
                    config.height = max(1, Int(window.frame.height * scale))
                    config.showsCursor = false
                    if #available(macOS 14.2, *) { config.ignoreShadowsSingleWindow = true }
                    do {
                        let capture = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: config)
                        guard !Task.isCancelled, self.generation == request else { return }
                        let image = NSImage(cgImage: capture, size: NSSize(width: capture.width, height: capture.height))
                        self.previewCache[entry.windowID] = image
                        self.previewDates[entry.windowID] = Date()
                        if let index = self.filtered.firstIndex(where: { $0.windowID == entry.windowID }), self.cards.indices.contains(index) {
                            self.cards[index].setPreview(image)
                        }
                    } catch { continue }
                }
            } catch {
                if self.generation == request { self.traceSwitch("preview unavailable; title-only fallback") }
            }
        }
    }

    private func updateSelection(scrollIntoView: Bool = true) {
        for (index, card) in cards.enumerated() { card.isSelected = index == selectedIndex }
        if scrollIntoView && cards.indices.contains(selectedIndex) { grid.scrollToVisible(cards[selectedIndex].frame.insetBy(dx: -4, dy: -4)) }
    }

    private func moveSelection(_ offset: Int) {
        guard !filtered.isEmpty else { return }
        selectedIndex = (selectedIndex + offset + filtered.count * max(columns, 1)) % filtered.count
        updateSelection()
    }

    private func beginCloseInteraction(modifiers: NSEvent.ModifierFlags) {
        if closeReleaseModifiers.isEmpty {
            closeReleaseModifiers = followsOption ? heldModifiers : modifiers.intersection([.command])
        }
        followsOption = false
    }

    /// Press the window's own red close control. The destination app retains
    /// ownership of save prompts, vetoes, and close-vs-hide behavior.
    private func closeWindowNatively(id: CGWindowID) {
        guard let index = filtered.firstIndex(where: { $0.windowID == id }), !closingWindows.contains(id) else { return }
        let entry = filtered[index]
        let request = generation
        let previousSelection = filtered.indices.contains(selectedIndex) ? filtered[selectedIndex].windowID : nil
        beginCloseInteraction(modifiers: NSEvent.modifierFlags)
        closingWindows.insert(id)
        // Closing is independent of selection/activation: leave the HUD in front.
        focusQueue.async {
            var raw: CFTypeRef?
            let query = AXUIElementCopyAttributeValue(entry.element, kAXCloseButtonAttribute as CFString, &raw)
            var result: AXError = query == .success ? .attributeUnsupported : query
            if query == .success, let raw = raw, CFGetTypeID(raw) == AXUIElementGetTypeID() {
                let control = raw as! AXUIElement
                var enabled: CFTypeRef?
                AXUIElementCopyAttributeValue(control, kAXEnabledAttribute as CFString, &enabled)
                if (enabled as? Bool) != false {
                    result = AXUIElementPerformAction(control, kAXPressAction as CFString)
                } else { result = .actionUnsupported }
            }
            CaptureDiagnostics.record("switcher native close window=\(id) result=\(result.rawValue)")
            let closeResult = result
            self.focusQueue.asyncAfter(deadline: .now() + 0.12) {
                var children: CFTypeRef?
                AXUIElementCopyAttributeValue(entry.element, kAXChildrenAttribute as CFString, &children)
                var needsConfirmation = (children as? [AXUIElement] ?? []).contains { child in
                    var role: CFTypeRef?
                    AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &role)
                    return (role as? String) == kAXSheetRole
                }
                let root = AXUIElementCreateApplication(entry.app.processIdentifier)
                AXUIElementSetMessagingTimeout(root, 0.15)
                var focused: CFTypeRef?
                if AXUIElementCopyAttributeValue(root, kAXFocusedWindowAttribute as CFString, &focused) == .success,
                   let focused = focused, CFGetTypeID(focused) == AXUIElementGetTypeID() {
                    var subrole: CFTypeRef?
                    AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXSubroleAttribute as CFString, &subrole)
                    var role: CFTypeRef?
                    AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXRoleAttribute as CFString, &role)
                    needsConfirmation = needsConfirmation || (subrole as? String) == kAXDialogSubrole || (role as? String) == kAXSheetRole
                }
                let showConfirmation = needsConfirmation
                DispatchQueue.main.async {
                    self.windowCacheRevision += 1
                    self.cacheDate = .distantPast
                    guard self.generation == request, self.panel?.isVisible == true else {
                        self.closingWindows.remove(id)
                        return
                    }
                    if showConfirmation {
                        self.closingWindows.remove(id)
                        self.dismiss(restoreFocus: false)
                        if #available(macOS 14.0, *) { NSApp.yieldActivation(to: entry.app) }
                        entry.app.activate(options: [.activateIgnoringOtherApps])
                    } else {
                        self.requestWindowSnapshot { [weak self] windows in
                            guard let self = self else { return }
                            self.closingWindows.remove(id)
                            guard self.generation == request, self.panel?.isVisible == true else { return }
                            let order = self.switchOrder.snapshot(available: windows.map(\.windowID), current: nil)
                            let byID = Dictionary(windows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
                            self.entries = order.compactMap { byID[$0] }
                            self.filtered = self.entries
                            self.selectedIndex = previousSelection.flatMap { selected in self.filtered.firstIndex(where: { $0.windowID == selected }) }
                                ?? min(index, max(0, self.filtered.count - 1))
                            self.lastPointerLocation = NSEvent.mouseLocation
                            self.renderGrid()
                            self.loadPreviews()
                        }
                    }
                    if closeResult != .success { NSSound.beep() }
                }
            }
        }
    }

    @objc private func commitSelection() {
        guard filtered.indices.contains(selectedIndex) else { dismiss(restoreFocus: true); return }
        let chosen = filtered[selectedIndex]
        dismiss(restoreFocus: false)
        let committedGeneration = generation
        focusTransitionGeneration = committedGeneration
        focusTransitionWindowID = chosen.windowID
        focusQueue.async {
            if chosen.minimized { AXUIElementSetAttributeValue(chosen.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse) }
            // Front the exact window even when Snaplet never showed/activated
            // its panel. App-only activation can be refused for a background agent.
            var serial = ProcessSerialNumber()
            let processStatus = windowSwitcherProcessSerial(chosen.app.processIdentifier, &serial)
            let frontStatus = processStatus == noErr
                ? windowSwitcherFrontWindow(&serial, chosen.windowID, 0x200) : CGError.failure
            if frontStatus != .success {
                DispatchQueue.main.sync {
                    NSApp.activate(ignoringOtherApps: true)
                    if #available(macOS 14.0, *) { NSApp.yieldActivation(to: chosen.app) }
                    _ = chosen.app.activate(options: [.activateIgnoringOtherApps])
                }
            }
            let keyStatus = processStatus == noErr
                ? WindowSwitcherNativeFocus.makeKey(process: &serial, window: chosen.windowID) : CGError.failure
            let raised = AXUIElementPerformAction(chosen.element, kAXRaiseAction as CFString)
            let main = AXUIElementSetAttributeValue(chosen.element, kAXMainAttribute as CFString, kCFBooleanTrue)
            CaptureDiagnostics.record("switcher focus target=\(chosen.windowID) pid=\(chosen.app.processIdentifier) front=\(frontStatus.rawValue) key=\(keyStatus.rawValue) raise=\(raised.rawValue) main=\(main.rawValue)")
            DispatchQueue.main.async {
                // App activation may briefly focus a different window in the
                // destination app. Commit only its final focused window.
                if self.focusTransitionGeneration == committedGeneration {
                    self.focusTransitionGeneration = nil
                    self.focusTransitionWindowID = nil
                }
                guard self.generation == committedGeneration, !self.isPresenting else { return }
                self.traceSwitch("focus result actualPid=\(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0) expectedPid=\(chosen.app.processIdentifier)")
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == chosen.app.processIdentifier {
                    let focused = self.noteFocusedWindow(in: chosen.app)
                    self.traceSwitch("key result actualWindow=\(focused ?? 0) expectedWindow=\(chosen.windowID)")
                }
                self.entries.removeAll()
                self.filtered.removeAll()
            }
        }
    }

    private func dismiss(restoreFocus: Bool) {
        guard !isDismissing else { return }
        isDismissing = true
        defer { isDismissing = false }
        closeReleaseModifiers = []
        generation += 1
        loading = false
        presentationWork?.cancel()
        presentationWork = nil
        previewTask?.cancel()
        previewTask = nil
        if let monitor = monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let outsideClickMonitor = outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
        panel?.orderOut(nil)
        if restoreFocus { previousApp?.activate(options: [.activateIgnoringOtherApps]) }
    }
}

@_silgen_name("_AXUIElementGetWindow")
private func windowSwitcherGetWindowID(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

// WindowServer's user-initiated, window-specific fronting operation, also used
// by native window switchers; no input events are injected.
@_silgen_name("GetProcessForPID")
private func windowSwitcherProcessSerial(_ pid: pid_t, _ process: UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

nonisolated private enum WindowSwitcherNativeFocus {
    typealias Front = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> Int32
    typealias PostRecord = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> Int32
    static let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL)
    static let front: Front? = {
        guard let handle = handle, let symbol = dlsym(handle, "_SLPSSetFrontProcessWithOptions") else { return nil }
        return unsafeBitCast(symbol, to: Front.self)
    }()
    static let postRecord: PostRecord? = {
        guard let handle = handle, let symbol = dlsym(handle, "SLPSPostEventRecordTo") else { return nil }
        return unsafeBitCast(symbol, to: PostRecord.self)
    }()

    static func makeKey(process: inout ProcessSerialNumber, window: CGWindowID) -> CGError {
        guard let post = postRecord else { return .failure }
        var record = WindowSwitchFocusRecord.make(window: window)
        let result = record.withUnsafeMutableBufferPointer { post(&process, $0.baseAddress!) }
        return CGError(rawValue: result) ?? .failure
    }
}

nonisolated private func windowSwitcherFrontWindow(_ process: UnsafeMutablePointer<ProcessSerialNumber>, _ window: CGWindowID, _ options: UInt32) -> CGError {
    guard let front = WindowSwitcherNativeFocus.front else { return .failure }
    return CGError(rawValue: front(process, window, options)) ?? .failure
}

@MainActor
private final class WindowSwitcherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Clip the effect itself as well as its layer: layer-only rounding can leave
/// square compositor fragments outside a borderless window's rounded corners.
@MainActor
private final class WindowSwitcherGlassView: NSVisualEffectView {
    init() {
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 18
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        let mask = NSImage(size: NSSize(width: 40, height: 40))
        mask.lockFocus()
        NSColor.black.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 40, height: 40), xRadius: 18, yRadius: 18).fill()
        mask.unlockFocus()
        mask.capInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        mask.resizingMode = .stretch
        maskImage = mask
        refreshBorder()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshBorder()
    }

    private func refreshBorder() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = NSColor.separatorColor.cgColor
        }
    }
}

@MainActor
private final class WindowThumbnailGrid: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
private final class WindowThumbnailCard: NSView {
    var onActivate: (() -> Void)?
    var onHover: (() -> Void)?
    var onClose: (() -> Void)?
    private let closeButton = NSButton()
    private var hoverTracking: NSTrackingArea?
    var isSelected = false { didSet { if oldValue != isSelected { updateAppearance() } } }
    private let backing = NSView(frame: NSRect(x: 10, y: 30, width: 220, height: 120))
    private let preview = NSImageView()
    private let placeholder = NSTextField(labelWithString: "")
    private let placeholderIcon = NSImageView()

    init(title: String, appName: String, icon: NSImage?, minimized: Bool, image: NSImage?) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(appName + " · " + title)
        let appIcon = NSImageView()
        appIcon.image = icon
        appIcon.frame = NSRect(x: 12, y: 158, width: 20, height: 20)
        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 12, weight: .medium)
        heading.textColor = .labelColor
        heading.lineBreakMode = .byTruncatingTail
        heading.frame = NSRect(x: 40, y: 157, width: 160, height: 20)
        backing.wantsLayer = true
        backing.layer?.cornerRadius = 6
        backing.layer?.masksToBounds = true
        preview.frame = backing.bounds.insetBy(dx: 2, dy: 2)
        preview.imageScaling = .scaleProportionallyUpOrDown
        placeholderIcon.image = icon
        placeholderIcon.frame = NSRect(x: 90, y: 42, width: 40, height: 40)
        placeholder.stringValue = minimized ? "窗口已最小化" : "正在加载预览…"
        placeholder.alignment = .center
        placeholder.textColor = .secondaryLabelColor
        placeholder.font = .systemFont(ofSize: 10)
        placeholder.frame = NSRect(x: 10, y: 18, width: 200, height: 16)
        backing.addSubview(preview)
        backing.addSubview(placeholderIcon)
        backing.addSubview(placeholder)
        let caption = NSTextField(labelWithString: appName + (minimized ? " · 已最小化" : ""))
        caption.font = .systemFont(ofSize: 10)
        caption.textColor = .secondaryLabelColor
        caption.lineBreakMode = .byTruncatingTail
        caption.frame = NSRect(x: 12, y: 8, width: 216, height: 15)
        closeButton.frame = NSRect(x: 208, y: 155, width: 24, height: 24)
        closeButton.title = ""
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "关闭窗口")
        closeButton.imageScaling = .scaleProportionallyDown
        closeButton.isBordered = false
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(closePressed)
        // Submit close before a simultaneous modifier release dismisses the HUD.
        closeButton.sendAction(on: .leftMouseDown)
        closeButton.toolTip = "关闭此窗口（由原软件处理保存提示）"
        closeButton.setAccessibilityLabel("关闭窗口：" + title)
        for view in [appIcon, heading, backing, caption, closeButton] { addSubview(view) }
        if let image = image { setPreview(image) }
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError() }

    func setPreview(_ image: NSImage) {
        preview.image = image
        placeholder.isHidden = true
        placeholderIcon.isHidden = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = isSelected
                ? NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
                : NSColor.controlBackgroundColor.withAlphaComponent(0.4).cgColor
            layer?.borderWidth = isSelected ? 3 : 1
            layer?.borderColor = isSelected ? NSColor.controlAccentColor.cgColor : NSColor.separatorColor.cgColor
            backing.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
        }
        setAccessibilityValue(isSelected ? "已选中" : "")
    }

    @objc private func closePressed() { onClose?() }

    func isClosePoint(_ point: NSPoint) -> Bool { closeButton.frame.contains(point) }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        return hit === closeButton ? hit : self
    }

    // The switcher may appear above another app without owning the first click.
    // Handle mouse-down explicitly; NSView's default forwards it to the window,
    // which can start a drag instead of delivering mouse-up back to this card.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = hoverTracking { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTracking = area
    }

    override func mouseEntered(with event: NSEvent) { onHover?() }
    override func mouseMoved(with event: NSEvent) { onHover?() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) { onActivate?() }
    override func mouseUp(with event: NSEvent) { }

    override func accessibilityPerformPress() -> Bool { onActivate?(); return true }
}


/// Exists only during explicit shortcut recording; swallows the recorded key before system shortcuts run.
@MainActor
final class WindowSwitcherKeyRecorder {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var preview: ((UInt32) -> Void)?
    private var completion: ((UInt32, UInt32) -> Void)?
    private var interruption: (() -> Void)?
    private var active = false

    func start(preview: @escaping (UInt32) -> Void, completion: @escaping (UInt32, UInt32) -> Void, interruption: @escaping () -> Void) -> Bool {
        stop()
        self.preview = preview
        self.completion = completion
        self.interruption = interruption
        let mask = CGEventMask((1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue))
        let callback: CGEventTapCallBack = { _, type, event, pointer in
            guard let pointer = pointer else { return Unmanaged.passUnretained(event) }
            let recorder = Unmanaged<WindowSwitcherKeyRecorder>.fromOpaque(pointer).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                DispatchQueue.main.async { if recorder.active { recorder.interruption?() } }
                return Unmanaged.passUnretained(event)
            }
            if type == .keyDown || type == .flagsChanged {
                let key = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
                let flags = event.flags
                var modifiers: UInt32 = 0
                if flags.contains(.maskCommand) { modifiers |= UInt32(cmdKey) }
                if flags.contains(.maskAlternate) { modifiers |= UInt32(optionKey) }
                if flags.contains(.maskControl) { modifiers |= UInt32(controlKey) }
                if flags.contains(.maskShift) { modifiers |= UInt32(shiftKey) }
                let capturedModifiers = modifiers
                DispatchQueue.main.async {
                    guard recorder.active else { return }
                    if type == .flagsChanged { recorder.preview?(capturedModifiers) }
                    else { recorder.completion?(key, capturedModifiers) }
                }
                return type == .flagsChanged ? Unmanaged.passUnretained(event) : nil
            }
            return type == .keyUp ? nil : Unmanaged.passUnretained(event)
        }
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                eventsOfInterest: mask, callback: callback, userInfo: pointer)
        if tap == nil {
            tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                    eventsOfInterest: mask, callback: callback, userInfo: pointer)
        }
        guard let tap = tap, let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else { stop(); return false }
        self.source = source
        active = true
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        active = false
        if let tap = tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        preview = nil
        completion = nil
        interruption = nil
    }
}

/// The event tap never runs UI/AX code. A dedicated run loop consumes the chord
/// immediately even while the main thread is busy rendering/querying windows.
nonisolated private final class WindowSwitcherSystemHotkeyTap: @unchecked Sendable {
    private let lock = NSLock()
    private var enabled = true
    private var stopped = false
    private var consumedTab = false
    private var sessionActive = false
    private var tap: CFMachPort?
    private var loop: CFRunLoop?
    private let onPress: @Sendable (Int) -> Void
    private let onRelease: @Sendable () -> Void

    init(onPress: @escaping @Sendable (Int) -> Void, onRelease: @escaping @Sendable () -> Void) {
        self.onPress = onPress
        self.onRelease = onRelease
    }

    func setEnabled(_ value: Bool) {
        lock.lock(); enabled = value; lock.unlock()
    }

    func start() -> Bool {
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            let callback: CGEventTapCallBack = { _, type, event, pointer in
                guard let pointer = pointer else { return Unmanaged.passUnretained(event) }
                return Unmanaged<WindowSwitcherSystemHotkeyTap>.fromOpaque(pointer).takeUnretainedValue().handle(type, event)
            }
            let mask = CGEventMask((1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue))
            let pointer = Unmanaged.passUnretained(self).toOpaque()
            let created = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                eventsOfInterest: mask, callback: callback, userInfo: pointer)
                ?? CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                    eventsOfInterest: mask, callback: callback, userInfo: pointer)
            guard let created = created,
                  let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0) else { ready.signal(); return }
            let current = CFRunLoopGetCurrent()!
            lock.lock()
            if stopped { lock.unlock(); CFMachPortInvalidate(created); ready.signal(); return }
            tap = created; loop = current
            lock.unlock()
            CFRunLoopAddSource(current, source, .commonModes)
            CGEvent.tapEnable(tap: created, enable: true)
            ready.signal()
            CFRunLoopRun()
            CGEvent.tapEnable(tap: created, enable: false)
            CFMachPortInvalidate(created)
            CFRunLoopRemoveSource(current, source, .commonModes)
            lock.lock(); tap = nil; loop = nil; lock.unlock()
        }
        thread.name = "Snaplet window shortcut"
        thread.qualityOfService = .userInteractive
        thread.start()
        guard ready.wait(timeout: .now() + 2) == .success else { stop(); return false }
        lock.lock(); let success = tap != nil; lock.unlock()
        return success
    }

    func stop() {
        lock.lock(); enabled = false; stopped = true; let current = loop; lock.unlock()
        if let current = current { CFRunLoopStop(current); CFRunLoopWakeUp(current) }
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        lock.lock()
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let current = stopped ? nil : tap
            lock.unlock()
            if let current = current { CGEvent.tapEnable(tap: current, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard enabled && !stopped else { lock.unlock(); return Unmanaged.passUnretained(event) }
        if type == .flagsChanged {
            let released = sessionActive && !event.flags.contains(.maskCommand)
            if released { sessionActive = false }
            lock.unlock()
            if released { onRelease() }
            return Unmanaged.passUnretained(event)
        }
        guard event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_Tab) else {
            lock.unlock(); return Unmanaged.passUnretained(event)
        }
        if type == .keyUp && consumedTab {
            consumedTab = false
            lock.unlock()
            return nil
        }
        let flags = event.flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift])
        guard type == .keyDown, flags == .maskCommand || flags == [.maskCommand, .maskShift] else {
            lock.unlock(); return Unmanaged.passUnretained(event)
        }
        // Check at the first key-down, not a polling timer: the first chord
        // after entering a remote client must reach that client unchanged.
        // An already-consumed local gesture retains its paired release.
        if !sessionActive && WindowSwitchRemotePolicy.isRemoteApplication(
            bundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier) {
            lock.unlock()
            return Unmanaged.passUnretained(event)
        }
        consumedTab = true
        sessionActive = true
        lock.unlock()
        onPress(flags.contains(.maskShift) ? -1 : 1)
        return nil
    }
}
