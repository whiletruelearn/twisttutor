import Foundation
import Observation
import CubeCore

public struct ScanPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    public func distance(to other: Self) -> Double { hypot(x - other.x, y - other.y) }
}

/// Normalized upright image coordinates, origin at top left. Clockwise corners.
public struct ScanQuad: Equatable, Sendable {
    public let corners: [ScanPoint]
    public init?(_ corners: [ScanPoint]) {
        guard corners.count == 4, corners.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }) else { return nil }
        let turns = (0..<4).map { i -> Double in
            let a = corners[i], b = corners[(i + 1) % 4], c = corners[(i + 2) % 4]
            return (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
        }
        guard turns.allSatisfy({ $0 > 0.0001 }) else { return nil }
        self.corners = corners
    }
    public var area: Double {
        abs((0..<4).reduce(0) { sum, i in
            let a = corners[i], b = corners[(i + 1) % 4]
            return sum + a.x * b.y - b.x * a.y
        }) / 2
    }
    /// Projective mapping from the rectified unit square to the original image.
    public func sourcePoint(u: Double, v: Double) -> ScanPoint {
        let a = corners[0], b = corners[1], c = corners[2], d = corners[3]
        let dx1 = b.x - c.x, dx2 = d.x - c.x, dx3 = a.x - b.x + c.x - d.x
        let dy1 = b.y - c.y, dy2 = d.y - c.y, dy3 = a.y - b.y + c.y - d.y
        let det = dx1 * dy2 - dx2 * dy1
        let g = (dx3 * dy2 - dx2 * dy3) / det
        let h = (dx1 * dy3 - dx3 * dy1) / det
        let divisor = g * u + h * v + 1
        return ScanPoint(((b.x - a.x + g * b.x) * u + (d.x - a.x + h * d.x) * v + a.x) / divisor,
                         ((b.y - a.y + g * b.y) * u + (d.y - a.y + h * d.y) * v + a.y) / divisor)
    }
}

public struct ScanRGB: Equatable, Sendable {
    public let red: Double, green: Double, blue: Double
    public init(_ red: Double, _ green: Double, _ blue: Double) { self.red = red; self.green = green; self.blue = blue }
    public var lab: SIMD3<Double> {
        func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let r = linear(red), g = linear(green), b = linear(blue)
        func f(_ t: Double) -> Double { t > 0.008856 ? pow(t, 1 / 3.0) : 7.787 * t + 16 / 116.0 }
        let x = f((0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047)
        let y = f(0.2126729 * r + 0.7151522 * g + 0.0721750 * b)
        let z = f((0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883)
        return SIMD3(116 * y - 16, 500 * (x - y), 200 * (y - z))
    }
    public func distance(to other: Self) -> Double {
        let delta = lab - other.lab
        return sqrt(delta.x * delta.x + delta.y * delta.y + delta.z * delta.z)
    }
}

public struct StickerSample: Equatable, Sendable {
    public let rgb: ScanRGB
    public let sourcePoint: ScanPoint
    public let spread: Double
    public init(rgb: ScanRGB, sourcePoint: ScanPoint, spread: Double) {
        self.rgb = rgb; self.sourcePoint = sourcePoint; self.spread = spread
    }
}

public struct FaceMeasurement: Sendable {
    public let quad: ScanQuad
    public let samples: [StickerSample]
    public let sharpness: Double
    public let darkFraction: Double
    public let clippedFraction: Double
    public let gridEvidence: Double
    public let angleRatio: Double
    public init(quad: ScanQuad, samples: [StickerSample], sharpness: Double, darkFraction: Double,
                clippedFraction: Double, gridEvidence: Double, angleRatio: Double) {
        self.quad = quad; self.samples = samples; self.sharpness = sharpness
        self.darkFraction = darkFraction; self.clippedFraction = clippedFraction
        self.gridEvidence = gridEvidence; self.angleRatio = angleRatio
    }
}

/// Starting thresholds, measured on rectified 180px images. Real-camera calibration is still required.
public struct ScanThresholds: Sendable {
    public var minimumArea = 0.07
    public var minimumAngleRatio = 0.60
    public var minimumSharpness = 0.0008
    public var maximumDarkFraction = 0.28
    public var maximumClippedFraction = 0.18
    public var minimumGridEvidence = 0.012
    public var maximumSpread = 0.11
    public var duplicateDeltaE = 10.0
    public var ambiguousDeltaE = 18.0
    public var stableSeconds = 0.85
    public var maximumFrameGap = 0.40
    public var maximumMotion = 0.018
    public var maximumColorChange = 7.0
    public init() {}
}

public enum ScanGuidance: String, Equatable, Sendable {
    case searching = "Fit one whole face inside the grid."
    case closer = "Move closer so the face fills the grid."
    case edges = "Move back slightly. Keep all four corners visible."
    case angle = "Face the camera straight toward the cube."
    case grid = "Show all nine stickers. Keep fingers off the face."
    case blur = "Hold the cube still and let the camera focus."
    case dark = "Move to brighter, even lighting."
    case glare = "Tilt slightly to avoid reflections."
    case colors = "Use even lighting so each sticker is clear."
    case duplicate = "This center was already scanned. Rotate to the next face."
    case ambiguous = "This center looks too similar to an earlier face. Check the face and lighting."
    case steady = "Keep it steady…"
    case captured = "Face captured."
}

public struct SampledFace: Sendable {
    public let face: CubeFaceID
    public let measurement: FaceMeasurement
    /// Guidance presents all faces in canonical outside-view orientation (including U and D).
    public var canonicalSamples: [StickerSample] { measurement.samples }
}

@MainActor @Observable
public final class ScanCapture {
    public static let sequence: [CubeFaceID] = [.front, .right, .back, .left, .up, .down]
    public private(set) var faces: [SampledFace] = []
    public private(set) var awaitingNext = false
    public private(set) var guidance: ScanGuidance = .searching
    public private(set) var latest: FaceMeasurement?
    public private(set) var stability = 0.0
    public private(set) var generation = UUID()
    public let thresholds: ScanThresholds
    private var anchor: FaceMeasurement?
    private var stableSince: Double?
    private var lastTime: Double?
    public init(thresholds: ScanThresholds = .init()) { self.thresholds = thresholds }
    public var complete: Bool { faces.count == 6 }
    public var currentFace: CubeFaceID { Self.sequence[min(faces.count, 5)] }
    public var acceptingFrames: Bool { !complete && !awaitingNext }
    public func invalidateFrames() {
        generation = UUID(); anchor = nil; stableSince = nil; lastTime = nil; stability = 0; latest = nil
    }
    public func reset() { faces = []; awaitingNext = false; guidance = .searching; invalidateFrames() }
    public func continueScanning() { guard awaitingNext, !complete else { return }; awaitingNext = false; guidance = .searching; invalidateFrames() }
    /// Retaking discards this face and subsequent faces, preserving the capture order.
    public func retake(from index: Int) {
        guard faces.indices.contains(index) else { return }
        faces.removeSubrange(index...); awaitingNext = true; guidance = .searching; invalidateFrames()
    }
    public func rejection(for m: FaceMeasurement) -> ScanGuidance? {
        let t = thresholds
        guard m.samples.count == 9 else { return .grid }
        guard [m.sharpness, m.darkFraction, m.clippedFraction, m.gridEvidence, m.angleRatio].allSatisfy({ $0.isFinite && $0 >= 0 }),
              m.samples.allSatisfy({ s in [s.rgb.red, s.rgb.green, s.rgb.blue, s.spread].allSatisfy { $0.isFinite && (0...1).contains($0) } }) else { return .colors }
        if m.quad.corners.contains(where: { $0.x < 0.025 || $0.y < 0.025 || $0.x > 0.975 || $0.y > 0.975 }) { return .edges }
        if m.quad.area < t.minimumArea { return .closer }
        if m.angleRatio < t.minimumAngleRatio { return .angle }
        if m.darkFraction > t.maximumDarkFraction { return .dark }
        if m.clippedFraction > t.maximumClippedFraction { return .glare }
        if m.gridEvidence < t.minimumGridEvidence { return .grid }
        if m.sharpness < t.minimumSharpness { return .blur }
        if m.samples.contains(where: { $0.spread > t.maximumSpread }) { return .colors }
        let center = m.samples[4]
        for face in faces {
            let previous = face.measurement.samples[4]
            let distance = center.rgb.distance(to: previous.rgb)
            if distance < t.duplicateDeltaE && max(center.spread, previous.spread) < 0.04 { return .duplicate }
            if distance < t.ambiguousDeltaE { return .ambiguous }
        }
        return nil
    }
    public func receive(_ measurement: FaceMeasurement?, at time: Double, generation token: UUID) {
        guard token == generation, acceptingFrames, time.isFinite else { return }
        latest = measurement
        guard let m = measurement else { reject(.searching); return }
        if let reason = rejection(for: m) { reject(reason); return }
        let continuous = lastTime.map { time > $0 && time - $0 <= thresholds.maximumFrameGap } ?? false
        let unmoved = anchor.map { a in
            zip(a.quad.corners, m.quad.corners).allSatisfy { $0.distance(to: $1) <= thresholds.maximumMotion } &&
            zip(a.samples, m.samples).allSatisfy { $0.rgb.distance(to: $1.rgb) <= thresholds.maximumColorChange }
        } ?? false
        if !continuous || !unmoved { anchor = m; stableSince = time }
        lastTime = time; guidance = .steady
        stability = min(1, max(0, (time - (stableSince ?? time)) / thresholds.stableSeconds))
        if stability >= 1 {
            faces.append(SampledFace(face: currentFace, measurement: m))
            awaitingNext = !complete; guidance = .captured; invalidateFrames()
        }
    }
    private func reject(_ reason: ScanGuidance) {
        guidance = reason; anchor = nil; stableSince = nil; lastTime = nil; stability = 0
    }
}
