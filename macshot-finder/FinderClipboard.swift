import Cocoa

/// One logical screenshot with image and file representations on the same item.
/// Multiple pasteboard items are separate attachments in applications like Messages.
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
        pasteboard.writeObjects([image])
    }
}
