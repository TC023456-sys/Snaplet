import Cocoa

/// Supplies a real PNG for Finder without putting file URLs on the image item.
/// Chat applications can continue reading PNG/TIFF bytes from the first item.
enum FinderClipboard {
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
        pasteboard.clearContents()
        var objects: [NSPasteboardWriting] = [image]
        if let fileURL { objects.append(fileURL as NSURL) }
        pasteboard.writeObjects(objects)
    }
}
