import XCTest
import CubeCore
import CubeValidation

final class ValidationTests: XCTestCase {
    func testPartialInputAndColorCounts() throws {
        XCTAssertEqual(CubeValidator.validateColors([]).diagnostics, [.stickerCount(actual: 0)])
        let cube = try CubeState.solved().replacingColor(at: 0, with: .red)
        let errors = CubeValidator.validate(cube).diagnostics
        XCTAssertTrue(errors.contains(.colorCount(color: .red, actual: 10)))
        XCTAssertTrue(errors.contains(.colorCount(color: .white, actual: 8)))
    }

    func testDuplicateCentersEvenWhenCountsAreBalanced() throws {
        var stickers = try CubeState.solved().stickers
        stickers.swapAt(4, 9)
        let cube = try CubeState(stickers: stickers)
        XCTAssertEqual(CubeValidator.validate(cube).diagnostics, [.duplicateCenters])
        XCTAssertThrowsError(try CubeConversion.cubies(from: cube))
    }

    func testSingleFlippedEdgeWithBalancedColors() throws {
        var eo = Array(repeating: 0, count: 12); eo[0] = 1
        let state = try fixture(eo: eo)
        XCTAssertEqual(CubeValidator.validate(state).diagnostics, [.edgeFlipParity])
        let cube = try CubeConversion.facelets(from: state)
        XCTAssertTrue(CubeValidator.validateColors(cube.stickers).isValid)
        XCTAssertEqual(CubeValidator.validate(cube).diagnostics, [.edgeFlipParity])
    }

    func testSingleTwistedCorner() throws {
        var co = Array(repeating: 0, count: 8); co[0] = 1
        let state = try fixture(co: co)
        XCTAssertEqual(CubeValidator.validate(try CubeConversion.facelets(from: state)).diagnostics, [.cornerTwistSum])
    }

    func testSwappedEdgesAndSwappedCornersBreakParity() throws {
        var ep = Array(0..<12); ep.swapAt(0, 1)
        var cp = Array(0..<8); cp.swapAt(0, 1)
        for state in [try fixture(ep: ep), try fixture(cp: cp)] {
            XCTAssertEqual(CubeValidator.validate(state).diagnostics, [.permutationParity])
            XCTAssertEqual(CubeValidator.validate(try CubeConversion.facelets(from: state)).diagnostics, [.permutationParity])
        }
        XCTAssertTrue(CubeValidator.validate(try fixture(cp: cp, ep: ep)).isValid)
    }

    func testDuplicateCornerAndEdgeIdentities() throws {
        var cp = Array(0..<8); cp[0] = 1
        var ep = Array(0..<12); ep[0] = 1
        let state = try fixture(cp: cp, ep: ep)
        XCTAssertEqual(CubeValidator.validate(state).diagnostics, [.duplicateCorners, .duplicateEdges])
        XCTAssertThrowsError(try CubeEncoding(CubeConversion.facelets(from: state)))
    }

    func testBalancedCountsDoNotHideDuplicatedPieces() throws {
        // Two pairs of opposite pieces duplicate one diagonal and remove the other,
        // preserving all six color totals while violating piece uniqueness.
        let corners = try fixture(cp: [0,0,2,3,4,5,6,6])
        let duplicateCube = try CubeConversion.facelets(from: corners)
        XCTAssertTrue(CubeValidator.validateColors(duplicateCube.stickers).isValid)
        XCTAssertEqual(CubeValidator.validate(duplicateCube).diagnostics, [.duplicateCorners])
        // Swapping two non-center stickers creates an impossible edge color combination.
        var stickers = try CubeState.solved().stickers
        stickers.swapAt(5, 12)
        let cube = try CubeState(stickers: stickers)
        XCTAssertTrue(CubeValidator.validateColors(stickers).isValid)
        XCTAssertFalse(CubeValidator.validate(cube).isValid)
    }

    func testReflectedCornerIsRejectedInsteadOfTreatedAsTwist() throws {
        var stickers = try CubeState.solved().stickers
        // URF's R1 and F3 swapped: same three colors, but reflected handedness.
        stickers.swapAt(9, 20)
        let report = CubeValidator.validate(try CubeState(stickers: stickers))
        XCTAssertEqual(report.diagnostics, [.unknownCorner(.urf, indices: [8,9,20])])
        XCTAssertFalse(report.diagnostics[0].message.isEmpty)
    }

    func testTwoFlipsAndCompensatingTwistsAreLegal() throws {
        var eo = Array(repeating: 0, count: 12); eo[0] = 1; eo[1] = 1
        var co = Array(repeating: 0, count: 8); co[0] = 1; co[1] = 2
        let cube = try CubeConversion.facelets(from: fixture(co: co, eo: eo))
        XCTAssertTrue(CubeValidator.validate(cube).isValid)
    }

    private func fixture(cp: [Int] = Array(0..<8), co: [Int] = Array(repeating: 0, count: 8), ep: [Int] = Array(0..<12), eo: [Int] = Array(repeating: 0, count: 12)) throws -> CubieState {
        try CubieState(cornerPermutation: cp, cornerOrientation: co, edgePermutation: ep, edgeOrientation: eo)
    }
}
