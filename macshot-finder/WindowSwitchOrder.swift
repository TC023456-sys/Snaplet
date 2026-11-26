import Foundation

/// Window identities, not application identities: two windows of one app are
/// separate tasks. A switch session gets a snapshot; only real focus commits
/// update the history used by the next session.
struct WindowSwitchOrder {
    private(set) var recent: [UInt32] = []

    mutating func noteFocus(_ id: UInt32) {
        recent.removeAll { $0 == id }
        recent.insert(id, at: 0)
    }

    mutating func snapshot(available: [UInt32], current: UInt32?) -> [UInt32] {
        let live = Set(available)
        recent.removeAll { !live.contains($0) }
        var known = Set(recent)
        // Newly discovered windows must not trail every previously seen window.
        // Keep their WindowServer front-to-back order, then preserve MRU among
        // existing windows. The actual current window remains first below.
        let discovered = available.filter { known.insert($0).inserted }
        recent.insert(contentsOf: discovered, at: 0)
        if let current = current, live.contains(current) { noteFocus(current) }
        return recent
    }

    static func initialIndex(in snapshot: [UInt32], current: UInt32?, keyboard: Bool, step: Int = 1, queued: Int = 0) -> Int {
        guard !snapshot.isEmpty else { return 0 }
        let startsOnCurrent = current != nil && snapshot.first == current
        let initial = keyboard && startsOnCurrent && snapshot.count > 1 ? step : 0
        return ((initial + queued) % snapshot.count + snapshot.count) % snapshot.count
    }
}

/// Distinguish repeated Tab in one hold from separate fast press/release gestures.
struct WindowSwitchKeystrokes {
    private(set) var initialStep = 1
    private(set) var extraSteps = 0
    private(set) var released = false
    private(set) var completed: [Int] = []
    mutating func begin(step: Int) { self = Self(); initialStep = step }
    mutating func press(step: Int) {
        if released {
            completed.append(initialStep + extraSteps)
            initialStep = step
            extraSteps = 0
            released = false
        } else { extraSteps += step }
    }
    mutating func release() { released = true }
}

/// WindowServer activation record. It carries only a window-specific down
/// transition outside all content; no matching up is sent, so this never clicks
/// a page control. ABI layout follows the native window-focus operation used
/// by Hammerspoon/yabai/AltTab (CGSEventRecord).
nonisolated enum WindowSwitchFocusRecord {
    static func make(window: UInt32) -> [UInt8] {
        var record = [UInt8](repeating: 0, count: 0x100)
        record[0x04] = 0xf8
        record[0x08] = 0x01
        record[0x3a] = 0x10
        var window = window
        withUnsafeBytes(of: &window) { record.replaceSubrange(0x3c..<0x40, with: $0) }
        var outside = CGPoint(x: 300_000, y: 300_000)
        withUnsafeBytes(of: &outside) { record.replaceSubrange(0x20..<0x30, with: $0) }
        return record
    }
}


/// Remote clients own their keyboard forwarding policy. Never consume their
/// window-switch chord, even when the remote session is not full screen.
nonisolated enum WindowSwitchRemotePolicy {
    static func isRemoteApplication(bundleIdentifier: String?) -> Bool {
        guard let id = bundleIdentifier?.lowercased() else { return false }
        return ["com.netease.uuremote", "de.raylink", "com.youqu.todesk.mac"].contains {
            id == $0 || id.hasPrefix($0 + ".")
        }
    }
}

