import Cocoa
let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
defer { try? FileManager.default.removeItem(at: folder) }
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let png = bitmap.representation(using: .png, properties: [:])!
let tiff = bitmap.tiffRepresentation!
let url = try FinderClipboard.createFile(pngData: png, directory: folder)
let saved = try Data(contentsOf: url)
precondition(saved == png)
let pb = NSPasteboard.withUniqueName()
defer { pb.releaseGlobally() }
FinderClipboard.write(pb, pngData: png, tiffData: tiff, fileURL: url)
precondition(pb.pasteboardItems!.count == 1)
precondition(pb.pasteboardItems![0].data(forType: .png) == png)
precondition(pb.pasteboardItems![0].string(forType: .fileURL) == url.absoluteString)
precondition(NSImage(pasteboard: pb) != nil)
let files = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as! [URL]
precondition(files == [url])
FinderClipboard.write(pb, pngData: png, tiffData: nil, fileURL: nil)
precondition(pb.pasteboardItems!.count == 1)
precondition(NSImage(pasteboard: pb) != nil)
print("PASS: one screenshot item, PNG/TIFF representations, Finder file URL, image decoding, file-write fallback")

// Cache cleanup only touches owned regular PNGs; current image always survives.
let unrelated = folder.appendingPathComponent("user-photo.png")
try png.write(to: unrelated)
let directoryNamedPNG = folder.appendingPathComponent("Screenshot-\(UUID().uuidString).png")
try FileManager.default.createDirectory(at: directoryNamedPNG, withIntermediateDirectories: false)
let link = folder.appendingPathComponent("Screenshot-\(UUID().uuidString).png")
try FileManager.default.createSymbolicLink(at: link, withDestinationURL: unrelated)
var generated = [url]
for index in 0..<6 {
    let file = try FinderClipboard.createFile(pngData: png, directory: folder)
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(index + 1))], ofItemAtPath: file.path)
    generated.append(file)
}
// Keep an older current item even when newer files exist.
FinderClipboard.prune(directory: folder, keeping: url, limit: 5)
precondition(generated.filter { FileManager.default.fileExists(atPath: $0.path) }.count == 5)
precondition(FileManager.default.fileExists(atPath: url.path))
FinderClipboard.prune(directory: folder, keeping: url, limit: 1)
precondition(generated.filter { FileManager.default.fileExists(atPath: $0.path) } == [url])
let retainedData = try Data(contentsOf: url)
precondition(retainedData == png)
precondition(FileManager.default.fileExists(atPath: unrelated.path))
precondition(FileManager.default.fileExists(atPath: directoryNamedPNG.path))
precondition((try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) != nil)
print("PASS: retention 5/1, current file protection, unrelated files, directories and symlinks untouched")
