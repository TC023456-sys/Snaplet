import Foundation

@main struct NewWindowOrderRegression {
    static func main() {
        var order = WindowSwitchOrder()
        assert(order.snapshot(available: [1, 2, 3], current: 1) == [1, 2, 3])
        // A new sibling/dialog missed by the focus observer must not be last.
        assert(order.snapshot(available: [4, 1, 2, 3], current: 1) == [1, 4, 2, 3])
        assert(order.snapshot(available: [4, 1, 2, 3], current: 4) == [4, 1, 2, 3])
        assert(order.snapshot(available: [5, 6, 4, 1, 2, 3], current: 4) == [4, 5, 6, 1, 2, 3])
        // Discovery does not reorder previously visited windows or duplicate IDs.
        assert(order.snapshot(available: [3, 2, 1, 4, 6, 5, 5], current: 4) == [4, 5, 6, 1, 2, 3])
        assert(order.snapshot(available: [4, 2], current: 4) == [4, 2])
        assert(order.snapshot(available: [], current: nil).isEmpty)
        print("PASS: newly discovered windows, sibling focus, MRU stability, deduplication and closure")
    }
}
