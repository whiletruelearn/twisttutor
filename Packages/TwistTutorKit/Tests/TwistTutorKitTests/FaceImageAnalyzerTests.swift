import XCTest
import CoreImage
@testable import AppWorkflow

final class FaceImageAnalyzerTests: XCTestCase {
    let colors: [[UInt8]] = [[200, 30, 30], [25, 165, 40], [30, 45, 200], [220, 190, 30], [210, 210, 210], [235, 100, 20], [45, 140, 65], [40, 60, 175], [190, 50, 50]]
    func fixture(gap: Int = 5, plain: Bool = false) -> CIImage {
        let width = 420
        var bytes = [UInt8](repeating: 255, count: width * width * 4)
        for y in 0..<width {
            for x in 0..<width {
                var color: [UInt8] = [100, 100, 100]
                if (60..<360).contains(x), (60..<360).contains(y) {
                    let col = (x - 60) / 100, row = (y - 60) / 100
                    let innerX = (x - 60) % 100, innerY = (y - 60) % 100
                    color = plain ? [200, 60, 30] : colors[row * 3 + col]
                    if !plain && (innerX < gap || innerX >= 100 - gap || innerY < gap || innerY >= 100 - gap) { color = [15, 15, 15] }
                }
                let i = (y * width + x) * 4
                bytes[i] = color[0]; bytes[i + 1] = color[1]; bytes[i + 2] = color[2]
            }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let cg = CGImage(width: width, height: width, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                         provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return CIImage(cgImage: cg)
    }
    func roundedFixture(missing: Set<Int> = [], roll: Double = 0) -> CIImage {
        // Rounded colored cubies with background between them and no outer frame.
        let size = CGSize(width: 400, height: 710)
        let canvas = CGContext(data: nil, width: 400, height: 710, bitsPerComponent: 8, bytesPerRow: 1600,
                               space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        canvas.setFillColor(CGColor(red: 0.28, green: 0.25, blue: 0.23, alpha: 1))
        canvas.fill(CGRect(origin: .zero, size: size))
        canvas.translateBy(x: 200, y: 355); canvas.rotate(by: roll * .pi / 180); canvas.translateBy(x: -200, y: -355)
        for row in 0..<3 {
            for col in 0..<3 {
                guard !missing.contains(row * 3 + col) else { continue }
                let c = colors[row * 3 + col]
                canvas.setFillColor(CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [CGFloat(c[0]) / 255, CGFloat(c[1]) / 255, CGFloat(c[2]) / 255, 1])!)
                let rect = CGRect(x: 48 + col * 100, y: 202 + (2 - row) * 100, width: 96, height: 96)
                canvas.addPath(CGPath(roundedRect: rect, cornerWidth: 16, cornerHeight: 16, transform: nil)); canvas.fillPath()
            }
        }
        return CIImage(cgImage: canvas.makeImage()!)
    }
    @MainActor func testRoundedStickerlessFaceWithoutOuterBorder() throws {
        for roll in [0.0, 7.0, -7.0] {
            let result = try XCTUnwrap(FaceImageAnalyzer().analyze(roundedFixture(roll: roll)))
            XCTAssertGreaterThan(result.quad.area, 0.25)
            XCTAssertNil(ScanCapture().rejection(for: result))
            for i in 0..<9 { XCTAssertEqual(result.samples[i].rgb.red, Double(colors[i][0]) / 255, accuracy: 0.04) }
        }
    }
    @MainActor func testPartialGridAndIsolatedStickerCannotBeCaptured() throws {
        for missing: Set<Int> in [[0], [0, 1, 2], [0, 1, 2, 3, 5, 6, 7, 8]] {
            if let result = try FaceImageAnalyzer().analyze(roundedFixture(missing: missing)) {
                XCTAssertNotNil(ScanCapture().rejection(for: result))
            }
        }
    }
    @MainActor func testRoundedGridRemainsStableAcrossSmallExposureChanges() throws {
        let capture = ScanCapture(), analyzer = FaceImageAnalyzer()
        let token = capture.generation
        for frame in 0...8 {
            let image = roundedFixture().applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: Double(frame % 3 - 1) * 0.03])
            let measurement = try XCTUnwrap(analyzer.analyze(image))
            capture.receive(measurement, at: Double(frame) * 0.15, generation: token)
        }
        XCTAssertEqual(capture.faces.count, 1)
    }
    func testVisionDetectsStickeredAndStickerlessFixturesWithCorrectRowOrder() throws {
        for gap in [5, 1] {
            let result = try XCTUnwrap(FaceImageAnalyzer().analyze(fixture(gap: gap)))
            XCTAssertEqual(result.samples.count, 9)
            XCTAssertGreaterThan(result.gridEvidence, ScanThresholds().minimumGridEvidence)
            XCTAssertGreaterThan(result.sharpness, ScanThresholds().minimumSharpness)
            for i in 0..<9 {
                let actual = result.samples[i].rgb
                XCTAssertEqual(actual.red, Double(colors[i][0]) / 255, accuracy: 0.035, "sticker \(i), gap \(gap)")
                XCTAssertEqual(actual.blue, Double(colors[i][2]) / 255, accuracy: 0.035)
                XCTAssertEqual(result.samples[i].sourcePoint.x, (60 + (Double(i % 3) + 0.5) * 100) / 420, accuracy: 0.025)
                XCTAssertEqual(result.samples[i].sourcePoint.y, (60 + (Double(i / 3) + 0.5) * 100) / 420, accuracy: 0.025)
            }
        }
    }
    func testPerspectiveCorrectionRetainsColorsAndOriginalCoordinates() throws {
        let source = fixture()
        let warped = source.applyingFilter("CIPerspectiveTransform", parameters: [
            "inputTopLeft": CIVector(x: 30, y: 405), "inputTopRight": CIVector(x: 390, y: 370),
            "inputBottomRight": CIVector(x: 410, y: 25), "inputBottomLeft": CIVector(x: 10, y: 15)
        ]).composited(over: CIImage(color: .gray).cropped(to: source.extent)).cropped(to: source.extent)
        let result = try XCTUnwrap(FaceImageAnalyzer().analyze(warped))
        XCTAssertGreaterThan(result.gridEvidence, ScanThresholds().minimumGridEvidence)
        for i in 0..<9 {
            XCTAssertEqual(result.samples[i].rgb.red, Double(colors[i][0]) / 255, accuracy: 0.05)
        }
        XCTAssertNotEqual(result.samples[0].sourcePoint.y, result.samples[2].sourcePoint.y)
    }
    func testPlainRectangleHasNoInventedGrid() throws {
        if let result = try FaceImageAnalyzer().analyze(fixture(plain: true)) {
            XCTAssertLessThan(result.gridEvidence, ScanThresholds().minimumGridEvidence)
        }
    }
    @MainActor func testDetectedFixturePassesGateAndSingleBadStickerDoesNot() throws {
        let capture = ScanCapture()
        let good = try XCTUnwrap(FaceImageAnalyzer().analyze(fixture()))
        XCTAssertNil(capture.rejection(for: good))
        for value: UInt8 in [0, 255] {
            var bytes = [UInt8](repeating: 150, count: 180 * 180 * 4)
            for y in 18..<42 {
                for x in 18..<42 {
                    for channel in 0..<3 { bytes[(y * 180 + x) * 4 + channel] = value }
                }
            }
            let bad = FaceImageAnalyzer.measure(bytes: bytes, quad: good.quad, imageAspect: 1)
            XCTAssertEqual(capture.rejection(for: bad), value == 0 ? .dark : .glare)
        }
    }
    func testBlurAndExposureMeasurements() throws {
        let analyzer = FaceImageAnalyzer()
        let good = try XCTUnwrap(analyzer.analyze(fixture()))
        let blurred = fixture().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 7]).cropped(to: fixture().extent)
        if let result = try analyzer.analyze(blurred) {
            XCTAssertLessThan(result.sharpness, good.sharpness / 5)
        }
        let dark = fixture().applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: -5])
        if let result = try analyzer.analyze(dark) { XCTAssertGreaterThan(result.darkFraction, ScanThresholds().maximumDarkFraction) }
    }
}
