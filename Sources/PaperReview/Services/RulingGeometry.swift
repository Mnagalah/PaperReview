import CoreGraphics
import CoreImage

/// Tracks long printed rules, not handwriting baselines. This is deterministic
/// image geometry; it never reads, corrects, or generates student characters.
nonisolated enum RulingGeometry {
    struct Curve: Codable {
        let a: Double; let b: Double; let c: Double
        let left: Double; let right: Double
        func y(_ x: Double) -> Double { let u = x - 0.5; return a * u * u + b * u + c }
    }
    static func curves(_ image: CGImage, diagnostics: ((String, Int) -> Void)? = nil) -> [Curve] {
        let width = min(1200, image.width), height = max(1, image.height * width / image.width)
        guard width >= 180, height >= 160 else { return [] }
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height)); return true
        }
        guard rendered else { return [] }
        let strips = 24, half = max(2, height / 240)
        var scores = [[Double]](repeating: [Double](repeating: 0, count: height), count: strips)
        for strip in 0..<strips {
            let start = strip * width / strips, end = (strip + 1) * width / strips
            for y in half..<(height - half) {
                var covered = 0, ink = 0
                for x in start..<end {
                    var found = false
                    for yy in (y - half)...(y + half) {
                        let offset = (yy * width + x) * 4
                        let gray = (Int(pixels[offset]) * 54 + Int(pixels[offset + 1]) * 183 + Int(pixels[offset + 2]) * 19) / 256
                        if gray < 155 { ink += 1; found = true }
                    }
                    if found { covered += 1 }
                }
                let count = Double(end - start)
                if Double(ink) / count < 3.5 { scores[strip][y] = Double(covered) / count }
            }
        }
        let middle = strips / 2
        var seeds: [Int] = [], run: [Int] = []
        for y in Int(Double(height) * 0.025)..<Int(Double(height) * 0.975) {
            if scores[middle][y] >= 0.82 { run.append(y) }
            else if !run.isEmpty { seeds.append(run[run.count / 2]); run = [] }
        }
        if !run.isEmpty { seeds.append(run[run.count / 2]) }
        diagnostics?("seeds", seeds.count)
        var found: [Curve] = []
        var longPaths = 0, fitRejected = 0
        let radius = max(8, height / 50)
        for seed in seeds {
            var points: [(Double, Double)] = [(Double(middle) + 0.5, Double(seed))]
            for direction in [-1, 1] {
                var previous = seed, velocity = 0
                var strip = middle + direction
                while strip >= 0 && strip < strips {
                    let predicted = previous + velocity
                    let low = max(half, predicted - radius), high = min(height - half - 1, predicted + radius)
                    guard low <= high else { break }
                    let best = (low...high).max { a, b in
                        scores[strip][a] - Double(abs(a - predicted)) / Double(radius) * 0.08
                            < scores[strip][b] - Double(abs(b - predicted)) / Double(radius) * 0.08
                    } ?? previous
                    guard scores[strip][best] >= 0.76 else { break }
                    points.append((Double(strip) + 0.5, Double(best)))
                    velocity = best - previous; previous = best; strip += direction
                }
            }
            points.sort { $0.0 < $1.0 }
            guard points.count >= 12, let first = points.first, let last = points.last,
                  (last.0 - first.0) / Double(strips) >= 0.45 else { continue }
            longPaths += 1
            let normalized = points.map { ($0.0 / Double(strips) - 0.5, 1 - $0.1 / Double(height)) }
            guard let fit = quadratic(normalized), abs(fit.0) < 0.35, abs(fit.1) < 0.35 else { continue }
            let error = normalized.map { abs(fit.0 * $0.0 * $0.0 + fit.1 * $0.0 + fit.2 - $0.1) }.reduce(0, +) / Double(points.count)
            guard error < 0.008 else { fitRejected += 1; continue }
            let curve = Curve(a: fit.0, b: fit.1, c: fit.2,
                left: max(0, (first.0 - 0.5) / Double(strips)), right: min(1, (last.0 + 0.5) / Double(strips)))
            if let same = found.firstIndex(where: { abs($0.c - curve.c) < 0.009 }) {
                if curve.right - curve.left > found[same].right - found[same].left { found[same] = curve }
            } else { found.append(curve) }
        }
        let sorted = found.sorted { $0.c > $1.c }
        diagnostics?("long_paths", longPaths); diagnostics?("fit_rejected", fitRejected); diagnostics?("accepted", sorted.count)
        guard sorted.count >= 8, let top = sorted.first, let bottom = sorted.last, top.c - bottom.c > 0.25 else { return [] }
        return sorted
    }
    static func quad(_ curves: [Curve]) -> PageRectifier.Quad? {
        guard let top = curves.first, let bottom = curves.last else { return nil }
        // A tracked path may stop at handwriting, not at the printed rule's real
        // endpoint. Unequal tracked lengths must not invent horizontal keystone.
        let lefts = curves.map(\.left).sorted(), rights = curves.map(\.right).sorted()
        let left = lefts[lefts.count / 2], right = rights[rights.count / 2]
        let quad = PageRectifier.Quad(topLeft: CGPoint(x: left, y: top.y(left)),
            topRight: CGPoint(x: right, y: top.y(right)), bottomRight: CGPoint(x: right, y: bottom.y(right)),
            bottomLeft: CGPoint(x: left, y: bottom.y(left)))
        return quad.area >= 0.2 ? quad : nil
    }
    static func flatten(_ image: CIImage, curves: [Curve]) -> CIImage? {
        guard curves.count >= 8 else { return nil }
        let count = max(2, curves.count / 3)
        func average(_ values: ArraySlice<Curve>) -> CIVector {
            let n = Double(values.count)
            return CIVector(x: values.map(\.a).reduce(0, +) / n, y: values.map(\.b).reduce(0, +) / n,
                z: values.map(\.c).reduce(0, +) / n, w: 0)
        }
        let top = average(curves.prefix(count)), bottom = average(curves.suffix(count))
        var displacement: CGFloat = 0
        for vector in [top, bottom] {
            for u: CGFloat in [-0.5, 0.5] {
                displacement = max(displacement, abs(vector.x * u * u + vector.y * u))
            }
        }
        guard displacement > 0.002, displacement < 0.08 else { return nil }
        let source = """
        kernel vec2 flattenRules(float width, float height, vec4 upper, vec4 lower) {
            vec2 p = destCoord();
            float u = p.x / width - 0.5;
            float t = clamp((p.y / height - lower.z) / max(upper.z - lower.z, 0.05), 0.0, 1.0);
            vec4 curve = mix(lower, upper, t);
            return p + vec2(0.0, (curve.x * u * u + curve.y * u) * height);
        }
        """
        guard let kernel = CIWarpKernel(source: source) else { return nil }
        let padding = ceil(displacement * image.extent.height) + 3
        let extent = image.extent.insetBy(dx: 0, dy: -padding)
        return kernel.apply(extent: extent, roiCallback: { _, rect in rect.insetBy(dx: 0, dy: -padding * 2) },
            image: image, arguments: [image.extent.width, image.extent.height, top, bottom])
    }
    private static func quadratic(_ points: [(Double, Double)]) -> (Double, Double, Double)? {
        var matrix = [[Double]](repeating: [Double](repeating: 0, count: 4), count: 3)
        for (x, y) in points {
            let basis = [x * x, x, 1.0]
            for row in 0..<3 {
                for column in 0..<3 { matrix[row][column] += basis[row] * basis[column] }
                matrix[row][3] += basis[row] * y
            }
        }
        for pivot in 0..<3 {
            let best = (pivot..<3).max { abs(matrix[$0][pivot]) < abs(matrix[$1][pivot]) } ?? pivot
            guard abs(matrix[best][pivot]) > 0.000001 else { return nil }
            matrix.swapAt(pivot, best)
            let divisor = matrix[pivot][pivot]
            for column in pivot..<4 { matrix[pivot][column] /= divisor }
            for row in 0..<3 where row != pivot {
                let factor = matrix[row][pivot]
                for column in pivot..<4 { matrix[row][column] -= factor * matrix[pivot][column] }
            }
        }
        return (matrix[0][3], matrix[1][3], matrix[2][3])
    }
}
