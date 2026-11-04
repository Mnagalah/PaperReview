import Foundation
import ImageIO
import Vision
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
request.recognitionLanguages = ["en-US"]; request.usesLanguageCorrection = false
try VNImageRequestHandler(cgImage: image).perform([request])
for observation in request.results ?? [] {
    let candidate = observation.topCandidates(1).first!
    print(candidate.confidence, candidate.string)
    if candidate.string.lowercased().contains("after lunch") {
        let box = observation.boundingBox
        let rect = CGRect(x: box.minX * Double(image.width), y: (1-box.maxY) * Double(image.height),
            width: box.width * Double(image.width), height: box.height * Double(image.height))
            .insetBy(dx: -12, dy: -12).integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let crop = image.cropping(to: rect)!
        let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[2]) as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, crop, nil); CGImageDestinationFinalize(destination)
    }
}
