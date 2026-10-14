import XCTest
import CubeCore
@testable import AppWorkflow

@MainActor final class ScanCaptureTests: XCTestCase {
    let quad = ScanQuad([.init(0.2, 0.2), .init(0.8, 0.2), .init(0.8, 0.8), .init(0.2, 0.8)])!
    let colors: [ScanRGB] = [.init(0.8, 0.1, 0.1), .init(0.1, 0.7, 0.1), .init(0.1, 0.1, 0.8), .init(0.8, 0.8, 0.1), .init(0.85, 0.85, 0.85), .init(1, 0.45, 0.05)]
    func measurement(_ color: ScanRGB? = nil, sharp: Double = 0.02, dark: Double = 0, glare: Double = 0,
                     grid: Double = 0.2, angle: Double = 1, spread: Double = 0.01) -> FaceMeasurement {
        FaceMeasurement(quad: quad, samples: (0..<9).map { i in
            StickerSample(rgb: color ?? colors[0], sourcePoint: quad.sourcePoint(u: (Double(i % 3) + 0.5) / 3, v: (Double(i / 3) + 0.5) / 3), spread: spread)
        }, sharpness: sharp, darkFraction: dark, clippedFraction: glare, gridEvidence: grid, angleRatio: angle)
    }
    func feed(_ capture: ScanCapture, _ m: FaceMeasurement, start: Double = 0) {
        let token = capture.generation
        for i in 0...8 { capture.receive(m, at: start + Double(i) * 0.15, generation: token) }
    }
    func testAllSixFacesGateAdvanceAndRetake() {
        let capture = ScanCapture()
        for i in 0..<6 {
            XCTAssertEqual(capture.currentFace, ScanCapture.sequence[i])
            feed(capture, measurement(colors[i]))
            XCTAssertEqual(capture.faces.count, i + 1)
            feed(capture, measurement(colors[i])) // no advance while waiting or complete
            XCTAssertEqual(capture.faces.count, i + 1)
            capture.continueScanning()
        }
        XCTAssertTrue(capture.complete)
        XCTAssertEqual(capture.faces.map(\.face), ScanCapture.sequence)
        capture.retake(from: 4)
        XCTAssertFalse(capture.complete)
        XCTAssertEqual(capture.faces.count, 4)
        XCTAssertEqual(capture.currentFace, .up)
        XCTAssertTrue(capture.awaitingNext)
        feed(capture, measurement(colors[5])) // cannot recapture the wrong face before orientation confirmation
        XCTAssertEqual(capture.faces.count, 4)
        capture.continueScanning()
        feed(capture, measurement(colors[4])); capture.continueScanning()
        feed(capture, measurement(colors[5]))
        XCTAssertTrue(capture.complete)
        capture.reset(); XCTAssertTrue(capture.faces.isEmpty)
    }
    func testEveryQualityRejectionPreventsCapture() {
        let examples: [(FaceMeasurement, ScanGuidance)] = [
            (measurement(sharp: 0), .blur), (measurement(dark: 0.9), .dark),
            (measurement(glare: 0.9), .glare), (measurement(grid: 0), .grid),
            (measurement(angle: 0.3), .angle), (measurement(spread: 0.5), .colors),
            (measurement(sharp: .nan), .colors)
        ]
        for (m, reason) in examples {
            let capture = ScanCapture(); feed(capture, m)
            XCTAssertEqual(capture.guidance, reason); XCTAssertTrue(capture.faces.isEmpty)
        }
    }
    func testDuplicateAndAmbiguousCentersCannotAdvance() {
        let capture = ScanCapture(); feed(capture, measurement()); capture.continueScanning()
        feed(capture, measurement()); XCTAssertEqual(capture.guidance, .duplicate)
        feed(capture, measurement(spread: 0.07)); XCTAssertEqual(capture.guidance, .ambiguous)
        XCTAssertEqual(capture.faces.count, 1)
    }
    func testLateFramesInterruptionAndTimeGapResetStability() {
        let capture = ScanCapture(), m = measurement()
        let old = capture.generation
        capture.receive(m, at: 0, generation: old); capture.receive(m, at: 0.3, generation: old)
        capture.invalidateFrames()
        capture.receive(m, at: 1.2, generation: old)
        XCTAssertTrue(capture.faces.isEmpty); XCTAssertNil(capture.latest)
        let token = capture.generation
        capture.receive(m, at: 2, generation: token); capture.receive(m, at: 20, generation: token)
        XCTAssertEqual(capture.stability, 0)
        capture.receive(nil, at: 20.1, generation: token)
        XCTAssertEqual(capture.guidance, .searching)
        capture.receive(m, at: 20.2, generation: token)
        XCTAssertEqual(capture.stability, 0)
        feed(capture, m, start: 21)
        XCTAssertEqual(capture.faces.count, 1)
        capture.retake(from: 0)
        capture.continueScanning()
        capture.receive(m, at: 30, generation: token)
        XCTAssertTrue(capture.faces.isEmpty)
    }
    func testColorMotionCannotAccumulateStableTime() {
        let capture = ScanCapture(), token = UUID()
        capture.receive(measurement(), at: 1, generation: token)
        XCTAssertNil(capture.latest)
        for i in 0...12 {
            capture.receive(measurement(colors[i % 2]), at: Double(i) * 0.15, generation: capture.generation)
        }
        XCTAssertTrue(capture.faces.isEmpty); XCTAssertEqual(capture.stability, 0)
    }
    func testProjectiveMappingAndInvalidGeometry() {
        XCTAssertNil(ScanQuad([.init(0, 0), .init(1, 1), .init(1, 0), .init(0, 1)]))
        XCTAssertNil(ScanQuad([.init(.nan, 0), .init(1, 0), .init(1, 1), .init(0, 1)]))
        let q = ScanQuad([.init(0.2, 0.1), .init(0.8, 0.2), .init(0.9, 0.9), .init(0.1, 0.8)])!
        for (i, uv) in [(0, (0.0, 0.0)), (1, (1.0, 0.0)), (2, (1.0, 1.0)), (3, (0.0, 1.0))] {
            XCTAssertLessThan(q.sourcePoint(u: uv.0, v: uv.1).distance(to: q.corners[i]), 0.000001)
        }
        XCTAssertEqual(quad.sourcePoint(u: 0.5, v: 0.5).x, 0.5, accuracy: 0.000001)
    }
    func testGuidedTopAndBottomTiltsPreserveCanonicalRowOrder() {
        // Return to F, then tilt U toward camera (+90 X) or D toward camera (-90 X).
        // Camera image right is +X and image down is -Y.
        for face in [CubeFaceID.up, .down] {
            for i in 0..<9 {
                let p = CubeRenderLayout.facelets[face.rawValue * 9 + i].position
                let after = face == .up ? SIMD3(p.x, -p.z, p.y) : SIMD3(p.x, p.z, -p.y)
                XCTAssertEqual(after.x, Float(i % 3 - 1))
                XCTAssertEqual(-after.y, Float(i / 3 - 1))
                XCTAssertEqual(after.z, 1)
            }
        }
    }
}
