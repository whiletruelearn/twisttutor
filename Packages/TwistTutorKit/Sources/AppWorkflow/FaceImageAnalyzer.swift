import Foundation
import CoreImage
import Vision

/// Synchronous worker; call on a serial background queue. No photos are stored or uploaded.
public final class FaceImageAnalyzer {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    public init() {}

    /// Input must already be upright and unmirrored; coordinates use this exact image.
    public func analyze(_ image: CIImage) throws -> FaceMeasurement? {
        let extent = image.extent
        guard extent.width >= 180, extent.height >= 180 else { return nil }
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 8
        request.minimumConfidence = 0.65
        request.minimumAspectRatio = 0.55
        request.minimumSize = 0.18
        request.quadratureTolerance = 25
        try VNImageRequestHandler(ciImage: image, orientation: .up).perform([request])
        // Prefer a complete centered face. Never synthesize a quad from the alignment overlay.
        let candidates = (request.results ?? []).sorted {
            func score(_ r: VNRectangleObservation) -> CGFloat {
                r.boundingBox.width * r.boundingBox.height - 0.4 * hypot(r.boundingBox.midX - 0.5, r.boundingBox.midY - 0.5)
            }
            return score($0) > score($1)
        }
        var fallback: FaceMeasurement?
        for rectangle in candidates {
            let points = [rectangle.topLeft, rectangle.topRight, rectangle.bottomRight, rectangle.bottomLeft]
            guard let quad = ScanQuad(points.map { ScanPoint(Double($0.x), Double(1 - $0.y)) }),
                  let result = sample(image, quad: quad) else { continue }
            if result.gridEvidence >= ScanThresholds().minimumGridEvidence { return result }
            // An isolated sticker is not a small cube. Do not turn it into "move closer" guidance.
            if fallback == nil && quad.area >= ScanThresholds().minimumArea { fallback = result }
        }
        // Rounded stickerless cubies often have no single outer rectangle. Fit a regular
        // lattice to observed edges near the guide, requiring all 12 outer/inner segments
        // in each direction. The guide only limits the search; it never supplies samples.
        for quad in gridCandidates(image) {
            if let result = sample(image, quad: quad) {
                if result.gridEvidence >= ScanThresholds().minimumGridEvidence { return result }
            }
        }
        return fallback
    }

    private func sample(_ image: CIImage, quad: ScanQuad) -> FaceMeasurement? {
        let extent = image.extent
        let pixels = quad.corners.map { CIVector(x: extent.minX + $0.x * extent.width, y: extent.minY + (1 - $0.y) * extent.height) }
        let corrected = image.applyingFilter("CIPerspectiveCorrection", parameters: [
            "inputTopLeft": pixels[0], "inputTopRight": pixels[1], "inputBottomRight": pixels[2], "inputBottomLeft": pixels[3]
        ])
        guard !corrected.extent.isEmpty, corrected.extent.width.isFinite, corrected.extent.height.isFinite else { return nil }
        guard let bytes = rgba(corrected, width: 180, height: 180) else { return nil }
        return Self.measure(bytes: bytes, quad: quad, imageAspect: Double(extent.width / extent.height))
    }

    private func rgba(_ image: CIImage, width: Int, height: Int) -> [UInt8]? {
        let normalized = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
            .transformed(by: CGAffineTransform(scaleX: Double(width) / image.extent.width, y: Double(height) / image.extent.height))
        guard let cg = context.createCGImage(normalized, from: CGRect(x: 0, y: 0, width: width, height: height), format: .RGBA8, colorSpace: colorSpace) else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let canvas = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: colorSpace,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            canvas.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return rendered ? bytes : nil
    }

    private func gridCandidates(_ image: CIImage) -> [ScanQuad] {
        let scale = 360 / max(image.extent.width, image.extent.height)
        let width = Int((image.extent.width * scale).rounded()), height = Int((image.extent.height * scale).rounded())
        guard let bytes = rgba(image, width: width, height: height) else { return [] }
        let short = Double(min(width, height))
        func difference(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
            let ax = Int(a.x.rounded()), ay = Int(a.y.rounded()), bx = Int(b.x.rounded()), by = Int(b.y.rounded())
            guard ax >= 0, ay >= 0, bx >= 0, by >= 0, ax < width, bx < width, ay < height, by < height else { return 0 }
            let ai = (ay * width + ax) * 4, bi = (by * width + bx) * 4
            let red = abs(Int(bytes[ai]) - Int(bytes[bi]))
            let green = abs(Int(bytes[ai + 1]) - Int(bytes[bi + 1]))
            let blue = abs(Int(bytes[ai + 2]) - Int(bytes[bi + 2]))
            return Double(max(red, green, blue)) / 255
        }
        var ranked: [(score: Double, quad: ScanQuad)] = []
        for degrees in stride(from: -10.0, through: 10.0, by: 2.5) {
            let angle = degrees * .pi / 180
            let right = SIMD2(cos(angle), sin(angle)), down = SIMD2(-sin(angle), cos(angle))
            for fraction in stride(from: 0.48, through: 0.90, by: 0.03) {
                let side = short * fraction
                for dx in -2...2 {
                    for dy in -2...2 {
                        let center = SIMD2(Double(width) / 2 + Double(dx) * short * 0.04, Double(height) / 2 + Double(dy) * short * 0.04)
                        let origin = center - (right + down) * (side / 2)
                        var weakest = 1.0
                        for vertical in [true, false] {
                            let normal = vertical ? right : down, tangent = vertical ? down : right
                            for line in 0...3 {
                                for cell in 0..<3 {
                                    var supported = 0, total = 0.0
                                    for t in [0.30, 0.50, 0.70] {
                                        let point = origin + normal * (Double(line) * side / 3) + tangent * ((Double(cell) + t) * side / 3)
                                        var edge = 0.0
                                        for offset in -5...5 {
                                            let at = point + normal * Double(offset)
                                            edge = max(edge, difference(at - normal * 1.5, at + normal * 1.5) * (1 - Double(abs(offset)) * 0.04))
                                        }
                                        if edge >= 0.045 { supported += 1 }
                                        total += edge
                                    }
                                    if supported < 3 { weakest = 0; break }
                                    weakest = min(weakest, total / 3)
                                }
                                if weakest == 0 { break }
                            }
                            if weakest == 0 { break }
                        }
                        guard weakest >= 0.045 else { continue }
                        let points = [origin, origin + right * side, origin + (right + down) * side, origin + down * side]
                        guard let quad = ScanQuad(points.map { ScanPoint($0.x / Double(width), $0.y / Double(height)) }) else { continue }
                        ranked.append((weakest, quad))
                    }
                }
            }
        }
        return ranked.sorted { $0.score > $1.score }.prefix(6).map(\.quad)
    }

    /// Internal deterministic pixel stage shared by real Vision output and fixture tests.
    static func measure(bytes: [UInt8], quad: ScanQuad, imageAspect: Double) -> FaceMeasurement {
        func rgb(_ x: Int, _ y: Int) -> SIMD3<Double> {
            let i = (y * 180 + x) * 4
            return SIMD3(Double(bytes[i]), Double(bytes[i + 1]), Double(bytes[i + 2])) / 255
        }
        func luminance(_ x: Int, _ y: Int) -> Double {
            let p = rgb(x, y); return p.x * 0.2126 + p.y * 0.7152 + p.z * 0.0722
        }
        var samples: [StickerSample] = []
        var worstDark = 0.0, worstClipped = 0.0
        for row in 0..<3 {
            for col in 0..<3 {
                var dark = 0, clipped = 0, count = 0
                var channels = [[Double]](repeating: [], count: 3)
                for y in (row * 60 + 18)..<(row * 60 + 42) {
                    for x in (col * 60 + 18)..<(col * 60 + 42) {
                        let p = rgb(x, y)
                        channels[0].append(p.x); channels[1].append(p.y); channels[2].append(p.z)
                        if max(p.x, p.y, p.z) < 0.13 { dark += 1 }
                        if min(p.x, p.y, p.z) > 0.985 { clipped += 1 }
                        count += 1
                    }
                }
                worstDark = max(worstDark, Double(dark) / Double(count))
                worstClipped = max(worstClipped, Double(clipped) / Double(count))
                channels = channels.map { $0.sorted() }
                let median = channels.map { $0[$0.count / 2] }
                let spread = channels.map { $0[$0.count * 9 / 10] - $0[$0.count / 10] }.max()!
                samples.append(StickerSample(rgb: ScanRGB(median[0], median[1], median[2]),
                    sourcePoint: quad.sourcePoint(u: (Double(col) + 0.5) / 3, v: (Double(row) + 0.5) / 3), spread: spread))
            }
        }
        // All four internal grid lines must be supported by actual image edges. A plain
        // rectangle cannot pass. Search locally for narrow seams on stickerless cubes.
        var lines: [Double] = []
        for vertical in [true, false] {
            for boundary in [60, 120] {
                var strongest = 0.0
                for offset in -7...7 {
                    let at = boundary + offset
                    var segments: [Double] = []
                    for cell in 0..<3 {
                        var strength = 0.0
                        var supported = 0
                        for along in (cell * 60 + 15)..<(cell * 60 + 45) {
                            let a = vertical ? rgb(at - 1, along) : rgb(along, at - 1)
                            let b = vertical ? rgb(at + 1, along) : rgb(along, at + 1)
                            let edge = max(abs(a.x - b.x), abs(a.y - b.y), abs(a.z - b.z))
                            strength += edge
                            if edge >= 0.012 { supported += 1 }
                        }
                        segments.append(supported >= 24 ? strength / 30 : 0)
                    }
                    // Require the seam across all three cells, not just a patch in the middle.
                    strongest = max(strongest, segments.min() ?? 0)
                }
                lines.append(strongest)
            }
        }
        var laplacian = 0.0
        for y in 1..<179 {
            for x in 1..<179 {
                let lap = 4 * luminance(x, y) - luminance(x - 1, y) - luminance(x + 1, y) - luminance(x, y - 1) - luminance(x, y + 1)
                laplacian += lap * lap
            }
        }
        let p = quad.corners.map { ScanPoint($0.x * imageAspect, $0.y) }
        let sides = (0..<4).map { p[$0].distance(to: p[($0 + 1) % 4]) }
        return FaceMeasurement(quad: quad, samples: samples, sharpness: laplacian / (178 * 178),
            darkFraction: worstDark, clippedFraction: worstClipped,
            gridEvidence: lines.min() ?? 0, angleRatio: (sides.min() ?? 0) / max(sides.max() ?? 1, 0.001))
    }
}
