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
            guard let quad = ScanQuad(points.map { ScanPoint(Double($0.x), Double(1 - $0.y)) }) else { continue }
            let pixels = points.map { CIVector(x: extent.minX + $0.x * extent.width, y: extent.minY + $0.y * extent.height) }
            let corrected = image.applyingFilter("CIPerspectiveCorrection", parameters: [
                "inputTopLeft": pixels[0], "inputTopRight": pixels[1], "inputBottomRight": pixels[2], "inputBottomLeft": pixels[3]
            ])
            guard !corrected.extent.isEmpty, corrected.extent.width.isFinite, corrected.extent.height.isFinite else { continue }
            let normalized = corrected.transformed(by: CGAffineTransform(translationX: -corrected.extent.minX, y: -corrected.extent.minY))
                .transformed(by: CGAffineTransform(scaleX: 180 / corrected.extent.width, y: 180 / corrected.extent.height))
            // CGImage's first row is the top row, matching the documented ScanPoint convention.
            guard let cg = context.createCGImage(normalized, from: CGRect(x: 0, y: 0, width: 180, height: 180), format: .RGBA8, colorSpace: colorSpace) else { continue }
            var bytes = [UInt8](repeating: 0, count: 180 * 180 * 4)
            let rendered = bytes.withUnsafeMutableBytes { buffer -> Bool in
                guard let canvas = CGContext(data: buffer.baseAddress, width: 180, height: 180, bitsPerComponent: 8,
                                              bytesPerRow: 180 * 4, space: colorSpace,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                canvas.draw(cg, in: CGRect(x: 0, y: 0, width: 180, height: 180))
                return true
            }
            guard rendered else { continue }
            let result = Self.measure(bytes: bytes, quad: quad, imageAspect: Double(extent.width / extent.height))
            if fallback == nil { fallback = result }
            if result.gridEvidence >= ScanThresholds().minimumGridEvidence { return result }
        }
        return fallback
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
