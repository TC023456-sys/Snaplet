import Foundation

/// A system capture callback may never arrive. Resolve independently of the
/// operation's lifetime; structured task groups would still await a hung child.
nonisolated final class CaptureDeadline<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value?, Never>?
    private var timer: DispatchWorkItem?

    private init(_ continuation: CheckedContinuation<Value?, Never>) {
        self.continuation = continuation
    }

    private func resolve(_ value: Value?) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        let timer = self.timer
        self.timer = nil
        lock.unlock()
        timer?.cancel()
        continuation?.resume(returning: value)
    }

    static func run(seconds: TimeInterval = 4,
                    start: @escaping (@escaping @Sendable (Value?) -> Void) -> Void) async -> Value? {
        await withCheckedContinuation { continuation in
            let deadline = CaptureDeadline(continuation)
            let timer = DispatchWorkItem { deadline.resolve(nil) }
            deadline.timer = timer
            DispatchQueue.global(qos: .userInitiated).asyncAfter(
                deadline: .now() + seconds, execute: timer)
            start { deadline.resolve($0) }
        }
    }
}

/// Small rolling local journal. No screenshots, window titles or user text.
nonisolated enum CaptureDiagnostics {
    private static let queue = DispatchQueue(label: "snaplet.capture-diagnostics")
    static func record(_ message: String) {
        queue.sync {
            let fm = FileManager.default
            guard let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
            let directory = support.appendingPathComponent("macshot", isDirectory: true)
            try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("capture-status.log")
            let line = "\(ISO8601DateFormatter().string(from: Date())) pid=\(ProcessInfo.processInfo.processIdentifier) \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            if let attributes = try? fm.attributesOfItem(atPath: url.path),
               let size = attributes[.size] as? NSNumber, size.intValue > 262144 {
                try? data.write(to: url, options: .atomic)
            } else if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                fm.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600])
            }
        }
    }
}
