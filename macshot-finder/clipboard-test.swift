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
