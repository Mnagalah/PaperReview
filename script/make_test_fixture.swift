import AppKit
let root = CommandLine.arguments.dropFirst().first ?? "."
let text = """
A Day at the Park

Last Sunday, I goed to the park with my freind.
The weather were sunny and warm. We plays football
for two hour. My sister don't like sports, so she
read a book under a tree.

After lunch, we see a beautifull bird near the lake.
I was very exciting. We taked many photos and
returned home at five o'clock. It was a happy day.
"""
let width = 1400, height = 1120
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0)!
let original = NSGraphicsContext(bitmapImageRep: bitmap)!
let context = original.cgContext
context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
NSColor.white.setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
let lines = text.components(separatedBy: "\n")
for (index, line) in lines.enumerated() {
    let font = NSFont(name: "Helvetica", size: index == 0 ? 44 : 38)!
    (line as NSString).draw(at: NSPoint(x: 90, y: 95 + index * 76), withAttributes: [.font: font, .foregroundColor: NSColor.black])
}
NSGraphicsContext.restoreGraphicsState()
let dir = URL(fileURLWithPath: root)
try bitmap.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent("synthetic-essay.png"))
try text.write(to: dir.appendingPathComponent("synthetic-essay.md"), atomically: true, encoding: .utf8)
