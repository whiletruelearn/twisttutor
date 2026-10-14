import XCTest
import simd
import CubeCore
import AppWorkflow

final class CubeRenderLayoutTests: XCTestCase {
    func testCanonicalFaceCornersAndAllLocations() {
        let layout = CubeRenderLayout.facelets
        XCTAssertEqual(layout.count, 54)
        XCTAssertEqual(Set(layout.map(\.position)).count, 26)
        // Outside-view top-left corners anchor all six faces independently of the engine.
        let corners: [SIMD3<Float>] = [[-1,1,-1], [1,1,1], [-1,1,1], [-1,-1,1], [-1,1,-1], [1,1,-1]]
        for face in CubeFaceID.allCases {
            XCTAssertEqual(layout[face.rawValue * 9].position, corners[face.rawValue])
            XCTAssertEqual(layout[face.rawValue * 9 + 4].position, CubeRenderLayout.axis(for: face))
        }
    }

    func testQuaternionAnimationEndpointsPreserveEveryStickerOverSequence() throws {
        var cube = try CubeState.solved(centerColors: [.blue,.yellow,.red,.green,.white,.orange])
        let allMoves = CubeFaceID.allCases.flatMap { face in TurnAmount.allCases.map { CubeMove(face, $0) } }
        let moves = allMoves + (try MoveNotation.parse("R U R' U' F2 D B' L2 U2 R2 D' F L' B2"))
        for move in moves {
            let axis = CubeRenderLayout.axis(for: move.face)
            let rotation = simd_quatf(angle: CubeRenderLayout.angle(for: move), axis: axis)
            let target = cube.applying(move)
            var affected = Set<SIMD3<Float>>()
            for source in CubeRenderLayout.facelets {
                let turns = simd_dot(source.position, axis) > 0.5
                if turns { affected.insert(source.position) }
                let position = turns ? rotation.act(source.position) : source.position
                let normal = turns ? rotation.act(source.normal) : source.normal
                let destination = try XCTUnwrap(CubeRenderLayout.facelets.first {
                    simd_distance($0.position, position) < 0.00001 && simd_distance($0.normal, normal) < 0.00001
                })
                XCTAssertEqual(cube.stickers[source.index], target.stickers[destination.index], move.notation)
            }
            XCTAssertEqual(affected.count, 9)
            cube = target
        }
    }
}

@MainActor final class CubePlaybackTests: XCTestCase {
    func testCommitAndOverlapProtection() throws {
        let initial = try CubeState.solved()
        let playback = CubePlayback(cube: initial)
        let turn = try XCTUnwrap(playback.begin(CubeMove(.right)))
        XCTAssertEqual(playback.cube, initial)
        XCTAssertNil(playback.begin(CubeMove(.up)))
        XCTAssertNil(playback.replay())
        XCTAssertFalse(playback.complete(UUID()))
        XCTAssertTrue(playback.complete(turn.id))
        XCTAssertFalse(playback.complete(turn.id))
        XCTAssertEqual(playback.cube, initial.applying(CubeMove(.right)))
    }

    func testReplayIsRepeatableWithoutApplyingAnotherMove() throws {
        let playback = CubePlayback(cube: try .solved())
        let turn = try XCTUnwrap(playback.begin(CubeMove(.front, .counterclockwise)))
        XCTAssertTrue(playback.complete(turn.id))
        for _ in 0..<5 {
            let replay = try XCTUnwrap(playback.replay())
            XCTAssertEqual(replay.source, turn.source)
            XCTAssertEqual(replay.target, turn.target)
            XCTAssertTrue(playback.complete(replay.id))
            XCTAssertEqual(playback.cube, turn.target)
            XCTAssertEqual(playback.lastTurn, turn)
        }
    }

    func testCancelResetAndStaleCompletion() throws {
        let initial = try CubeState.solved()
        let playback = CubePlayback(cube: initial)
        let cancelled = try XCTUnwrap(playback.begin(CubeMove(.back, .half)))
        playback.cancel()
        XCTAssertEqual(playback.cube, initial)
        let current = try XCTUnwrap(playback.begin(CubeMove(.left)))
        XCTAssertFalse(playback.complete(cancelled.id))
        XCTAssertTrue(playback.complete(current.id))
        let replay = try XCTUnwrap(playback.replay())
        playback.cancel()
        XCTAssertEqual(playback.cube, current.target)
        XCTAssertFalse(playback.complete(replay.id))
        let pending = try XCTUnwrap(playback.begin(CubeMove(.down)))
        playback.replace(with: initial)
        XCTAssertFalse(playback.complete(pending.id))
        XCTAssertEqual(playback.cube, initial)
        XCTAssertNil(playback.replay())
    }
}
