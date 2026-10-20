import Foundation

@main struct DeadlineTests {
    static func main() async {
        let success = await CaptureDeadline<Int>.run(seconds: 0.05) { finish in finish(42) }
        precondition(success == 42)
        let start = Date()
        let missing = await CaptureDeadline<Int>.run(seconds: 0.02) { _ in }
        precondition(missing == nil && Date().timeIntervalSince(start) < 1)
        let late = await CaptureDeadline<Int>.run(seconds: 0.01) { finish in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.04) { finish(1); finish(2) }
        }
        precondition(late == nil)
        for _ in 0..<100 {
            let value = await CaptureDeadline<Int>.run(seconds: 0.001) { finish in
                DispatchQueue.global().async { finish(1); finish(2) }
            }
            precondition(value == nil || value == 1)
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        print("PASS: immediate success, missing callback timeout, late/duplicate callbacks and 100 races")
    }
}
