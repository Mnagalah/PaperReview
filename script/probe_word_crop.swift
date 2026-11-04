import AppKit
import ImageIO
import Vision
let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, nil)!
let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
request.recognitionLanguages = ["en-US"]; request.usesLanguageCorrection = false
try VNImageRequestHandler(cgImage: image).perform([request])
for observation in request.results ?? [] {
    let candidate = observation.topCandidates(1).first!
    guard let range = candidate.string.range(of: "beautifull"), let word = try candidate.boundingBox(for: range) else { continue }
    let b = word.boundingBox
    let rect = CGRect(x: b.minX * Double(image.width), y: (1-b.maxY) * Double(image.height),
        width: b.width * Double(image.width), height: b.height * Double(image.height))
        .insetBy(dx: -8, dy: -12).integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let crop = image.cropping(to: rect)!
    let output = URL(fileURLWithPath: CommandLine.arguments[2])
    let target = CGImageDestinationCreateWithURL(output.appendingPathComponent("word-original.png") as CFURL,"public.png" as CFString,1,nil)!
    CGImageDestinationAddImage(target,crop,nil);CGImageDestinationFinalize(target)
    for text in ["beautiful", "beautifull"] {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:320,pixelsHigh:100,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        let graphics = NSGraphicsContext(bitmapImageRep:bitmap)!
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=graphics
        NSColor.white.setFill();NSRect(x:0,y:0,width:320,height:100).fill()
        (text as NSString).draw(at:NSPoint(x:16,y:28),withAttributes:[.font:NSFont(name:"Helvetica",size:46)!, .foregroundColor:NSColor.black])
        NSGraphicsContext.restoreGraphicsState()
        try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("word-render-\(text).png"))
    }
    print("word rect",rect)
}
