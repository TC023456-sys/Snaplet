import Foundation
@main struct WindowOrderTests {
    static func main() {
        var order = WindowSwitchOrder()
        let first = order.snapshot(available: [101, 102, 103], current: 101)
        assert(first == [101, 102, 103])
        assert(WindowSwitchOrder.initialIndex(in: first, current: 101, keyboard: true) == 1)
        order.noteFocus(102)
        let second = order.snapshot(available: [103, 101, 102], current: 102)
        assert(second == [102, 101, 103], "CG layer order must not replace real focus history")
        assert(second[WindowSwitchOrder.initialIndex(in: second, current: 102, keyboard: true)] == 101)
        order.noteFocus(101)
        assert(order.snapshot(available: [103, 102, 101], current: 101) == first, "quick toggle returns to the other recent window")
        order.noteFocus(103)
        assert(order.snapshot(available: [101, 102, 103], current: 103) == [103, 101, 102])
        assert(first == [101, 102, 103], "an open session snapshot remains frozen")
        assert(WindowSwitchOrder.initialIndex(in: first, current: 101, keyboard: true, queued: 1) == 2)
        assert(WindowSwitchOrder.initialIndex(in: first, current: 101, keyboard: true, step: -1) == 2)
        assert(WindowSwitchOrder.initialIndex(in: first, current: nil, keyboard: true) == 0)
        assert(WindowSwitchOrder.initialIndex(in: first, current: 101, keyboard: false) == 0)
        assert(order.snapshot(available: [101, 104], current: 101) == [101, 104], "remove closed windows and append unvisited new windows")
        assert(order.snapshot(available: [104, 101], current: 101) == [101, 104], "stable order without a focus change")
        assert(order.snapshot(available: [], current: nil).isEmpty)
        assert(WindowSwitchOrder.initialIndex(in: [], current: nil, keyboard: true) == 0)
        var keys = WindowSwitchKeystrokes()
        keys.begin(step: 1)
        keys.release()
        assert(keys.released && keys.completed.isEmpty)
        keys.press(step: 1)
        assert(!keys.released && keys.completed == [1] && keys.extraSteps == 0)
        keys.release()
        keys.press(step: 1)
        assert(keys.completed == [1, 1], "separate quick taps must not become one held chord")
        var toggles = WindowSwitchOrder()
        var snapshot = toggles.snapshot(available: [1, 2, 3], current: 1)
        var current: UInt32? = 1
        for step in keys.completed {
            let target = snapshot[WindowSwitchOrder.initialIndex(in: snapshot, current: current, keyboard: true, step: step)]
            toggles.noteFocus(target); current = target
            snapshot = toggles.snapshot(available: [1, 2, 3], current: current)
        }
        assert(current == 1 && snapshot == [1, 2, 3])
        keys.begin(step: 1)
        keys.press(step: 1)
        assert(keys.completed.isEmpty && keys.extraSteps == 1, "holding and pressing twice selects the third window")
        let packet = WindowSwitchFocusRecord.make(window: 0x12345678)
        assert(packet.count == 256)
        assert(packet[4] == 0xf8 && packet[8] == 1 && packet[0x3a] == 0x10)
        assert(Array(packet[0x3c..<0x40]) == [0x78, 0x56, 0x34, 0x12])
        var expectedPoint = CGPoint(x: 300_000, y: 300_000)
        let pointBytes = withUnsafeBytes(of: &expectedPoint) { Array($0) }
        assert(Array(packet[0x20..<0x30]) == pointBytes)
        assert(packet[8] != 2, "never generate a mouse-up/click on page content")
        print("25 window-order, quick-tap, and key-window record checks passed")
    }
}
