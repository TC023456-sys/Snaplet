import Cocoa

/// One logical screenshot with image and file representations on the same item.
/// Multiple pasteboard items are separate attachments in applications like Messages.
enum FinderClipboard {
    nonisolated static let retentionKey = "SnapletFinderClipboardRetention"
    nonisolated static var retentionCount: Int {
        let value = UserDefaults.standard.object(forKey: retentionKey) as? Int ?? 1
        return [1, 5, 10, 20].contains(value) ? value : 1
    }

    /// Only our generated regular PNGs are eligible. Never follow symlinks or
    /// touch screenshot history, exported images or unrelated files.
    nonisolated static func prune(directory: URL, keeping current: URL, limit: Int) {
        let manager = FileManager.default
        guard let files = try? manager.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]) else { return }
        let candidates = files.compactMap { url -> (URL, Date)? in
            let name = url.lastPathComponent
            guard name.hasPrefix("Screenshot-"), name.hasSuffix(".png"),
                  UUID(uuidString: String(name.dropFirst(11).dropLast(4))) != nil,
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true else { return nil }
            return (url, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.1 == $1.1 ? $0.0.lastPathComponent < $1.0.lastPathComponent : $0.1 > $1.1 }
        let others = candidates.filter { $0.0.standardizedFileURL != current.standardizedFileURL }
        for (url, _) in others.dropFirst(max(1, limit) - 1) {
            try? manager.removeItem(at: url)
        }
    }
    nonisolated static var directoryURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FinderClipboard", isDirectory: true)
    }

    nonisolated static func createFile(pngData: Data, directory: URL? = nil) throws -> URL {
        let manager = FileManager.default
        let folder = directory ?? directoryURL
        try manager.createDirectory(at: folder, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        let url = folder.appendingPathComponent("Screenshot-\(UUID().uuidString).png")
        try pngData.write(to: url, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }

    static func write(_ pasteboard: NSPasteboard, pngData: Data, tiffData: Data?, fileURL: URL?) {
        let image = NSPasteboardItem()
        image.setData(pngData, forType: .png)
        if let tiffData { image.setData(tiffData, forType: .tiff) }
        if let fileURL {
            let url = fileURL as NSURL
            for type in url.writableTypes(for: pasteboard) {
                if let value = url.pasteboardPropertyList(forType: type) {
                    if let string = value as? String {
                        image.setString(string, forType: type)
                    } else if let data = value as? Data {
                        image.setData(data, forType: type)
                    } else {
                        image.setPropertyList(value, forType: type)
                    }
                }
            }
        }
        pasteboard.clearContents()
        if pasteboard.writeObjects([image]), let fileURL {
            prune(directory: fileURL.deletingLastPathComponent(), keeping: fileURL, limit: retentionCount)
        }
    }
}
