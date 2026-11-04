import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

/// Geometry only. No generated pixels or additional recognition model is used.
nonisolated enum PageRectifier {
    struct Quad {
        let topLeft: CGPoint; let topRight: CGPoint; let bottomRight: CGPoint; let bottomLeft: CGPoint
        var points: [CGPoint] { [topLeft, topRight, bottomRight, bottomLeft] }
        init(_ rectangle: VNRectangleObservation) {
            topLeft = rectangle.topLeft; topRight = rectangle.topRight
            bottomRight = rectangle.bottomRight; bottomLeft = rectangle.bottomLeft
        }
        init(topLeft: CGPoint, topRight: CGPoint, bottomRight: CGPoint, bottomLeft: CGPoint) {
            self.topLeft = topLeft; self.topRight = topRight; self.bottomRight = bottomRight; self.bottomLeft = bottomLeft
        }
        var area: Double {
            abs(points.indices.reduce(0.0) { sum, index in
                let a = points[index], b = points[(index + 1) % 4]
                return sum + a.x * b.y - b.x * a.y
            }) / 2
        }
        func contains(_ point: CGPoint) -> Bool {
            let crosses = points.indices.map { index in
                let a = points[index], b = points[(index + 1) % 4]
                return (b.x - a.x) * (point.y - a.y) - (b.y - a.y) * (point.x - a.x)
            }
            return crosses.allSatisfy { $0 >= 0 } || crosses.allSatisfy { $0 <= 0 }
        }
    }
    struct Result { let image: CIImage; let method: String; let quad: Quad?; let cropped: Bool }

    static func rectify(_ image: CGImage, text: [VNRecognizedTextObservation]) throws -> Result {
        let input = CIImage(cgImage: image)
        let document = VNDetectDocumentSegmentationRequest()
        let frames = VNDetectRectanglesRequest()
        frames.maximumObservations = 24; frames.minimumConfidence = 0.75
        frames.minimumSize = 0.08; frames.minimumAspectRatio = 0.1; frames.quadratureTolerance = 30
        do { try VNImageRequestHandler(cgImage: image).perform([document, frames]) }
        catch { throw PhotoError.visionStage("纸面定位", error.localizedDescription) }
        if let paper = document.results?.first, paper.confidence >= 0.85, Quad(paper).area >= 0.60 {
            let containsAll = text.allSatisfy { observation in
               let box = observation.boundingBox.insetBy(dx: -0.005, dy: -0.005)
               return [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                       CGPoint(x: box.minX, y: box.maxY), CGPoint(x: box.maxX, y: box.maxY)].allSatisfy { Quad(paper).contains($0) }
            }
            return try correct(input, quad: Quad(paper), crop: containsAll,
                method: containsAll ? "paper_edges" : "paper_reference")
        }
        let anchors = (frames.results ?? []).filter { frame in
            let quad = Quad(frame)
            return quad.area >= 0.10 && frame.boundingBox.width >= 0.5 && frame.boundingBox.height >= 0.1
                && text.filter { quad.contains(CGPoint(x: $0.boundingBox.midX, y: $0.boundingBox.midY)) }.count >= 3
        }
        if let frame = anchors.max(by: { Quad($0).area < Quad($1).area }) {
            // A printed frame establishes a plane, not a crop boundary. The essay
            // below/outside that frame must stay in the rectified photograph.
            return try correct(input, quad: Quad(frame), crop: false, method: "printed_frame")
        }
        if let quad = RulingGeometry.quad(RulingGeometry.curves(image)) {
            return try correct(input, quad: quad, crop: false, method: "ruled_lines")
        }
        let angles = text.filter { $0.boundingBox.width >= 0.35 }.map { observation in
            atan2((observation.topRight.y - observation.topLeft.y) * Double(image.height),
                  (observation.topRight.x - observation.topLeft.x) * Double(image.width))
        }.sorted()
        if angles.count >= 3, let first = angles.first, let last = angles.last, last - first < 0.045 {
            let angle = angles[angles.count / 2]
            if abs(angle) > 0.006 && abs(angle) < 0.20 {
                return Result(image: normalized(input.transformed(by: CGAffineTransform(rotationAngle: -angle))),
                    method: "deskew", quad: nil, cropped: false)
            }
        }
        return Result(image: input, method: "unchanged", quad: nil, cropped: false)
    }

    static func flattenRulings(_ result: Result, context: CIContext) -> Result {
        guard let cg = context.createCGImage(result.image, from: result.image.extent),
              let flat = RulingGeometry.flatten(result.image, curves: RulingGeometry.curves(cg)) else { return result }
        return Result(image: normalized(flat), method: result.method + "+curve", quad: result.quad, cropped: result.cropped)
    }

    static func correct(_ image: CIImage, quad: Quad, crop: Bool, method: String) throws -> Result {
        let filter = CIFilter.perspectiveCorrection()
        let extent = image.extent
        func pixel(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x * extent.width, y: point.y * extent.height) }
        filter.inputImage = image; filter.crop = crop
        filter.topLeft = pixel(quad.topLeft); filter.topRight = pixel(quad.topRight)
        filter.bottomLeft = pixel(quad.bottomLeft); filter.bottomRight = pixel(quad.bottomRight)
        guard let output = filter.outputImage, output.extent.width.isFinite, output.extent.height.isFinite,
              output.extent.width > 0, output.extent.height > 0,
              output.extent.width <= extent.width * 3, output.extent.height <= extent.height * 3 else { throw PhotoError.renderFailed }
        return Result(image: normalized(output), method: method, quad: quad, cropped: crop)
    }

    private static func normalized(_ image: CIImage) -> CIImage {
        let bounds = image.extent.integral
        let white = CIImage(color: .white).cropped(to: bounds)
        return image.composited(over: white).cropped(to: bounds)
            .transformed(by: CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
    }

}
