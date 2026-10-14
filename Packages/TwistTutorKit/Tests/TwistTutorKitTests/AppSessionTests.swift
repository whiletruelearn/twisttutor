import XCTest
import AppWorkflow
import CubeCore

@MainActor
final class AppSessionTests: XCTestCase {
    func testOrderedSixFaceWorkflowAndSolveCompletion() throws {
        let session = AppSession()
        XCTAssertEqual(session.phase, .idle)
        session.start(.solve)
        try scanSolvedCube(into: session)
        XCTAssertEqual(session.phase, .validatingCube)
        XCTAssertNil(session.nextFace)
        try session.validateCurrentCube()
        XCTAssertEqual(session.phase, .cubeReady)
        XCTAssertTrue(session.validation?.isValid == true)
        let token = try session.beginSolutionCalculation()
        XCTAssertEqual(session.phase, .calculatingSolution)
        XCTAssertTrue(session.finishSolutionCalculation(token: token, verified: false))
        XCTAssertEqual(session.phase, .cubeReady)
        XCTAssertNotNil(session.errorMessage)
        let retry = try session.beginSolutionCalculation()
        XCTAssertFalse(session.finishSolutionCalculation(token: token, verified: true))
        XCTAssertTrue(session.finishSolutionCalculation(token: retry, verified: true))
        XCTAssertEqual(session.phase, .solving)
        try session.complete()
        XCTAssertEqual(session.phase, .completed)
    }

    func testTeachingDoesNotUseQuickSolver() throws {
        let session = AppSession()
        session.start(.learn)
        try scanSolvedCube(into: session)
        try session.validateCurrentCube()
        XCTAssertThrowsError(try session.beginSolutionCalculation()) { XCTAssertEqual($0 as? WorkflowError, .wrongExperienceMode) }
        try session.beginTeaching()
        XCTAssertEqual(session.phase, .teaching)
        session.rescan()
        XCTAssertEqual(session.mode, .learn)
        XCTAssertEqual(session.phase, .scanning)
        XCTAssertTrue(session.captures.isEmpty)
    }

    func testInvalidTransitionsAndWrongFaceCannotAdvance() throws {
        let session = AppSession()
        XCTAssertThrowsError(try session.beginFaceProcessing())
        XCTAssertThrowsError(try session.complete())
        session.start(.solve)
        XCTAssertThrowsError(try session.continueScanning())
        let token = try session.beginFaceProcessing()
        XCTAssertThrowsError(try session.beginFaceProcessing())
        let solved = try CubeState.solved()
        let wrong = CapturedFace(face: .up, imageFace: solved[.up], rotationToCanonical: .none)
        XCTAssertThrowsError(try session.acceptFace(wrong, token: token))
        XCTAssertTrue(session.captures.isEmpty)
        session.rejectFace(token: token)
        XCTAssertEqual(session.phase, .scanning)
        XCTAssertNotNil(session.errorMessage)
        let nextToken = try session.beginFaceProcessing()
        let front = CapturedFace(face: .front, imageFace: solved[.front], rotationToCanonical: .none)
        XCTAssertTrue(try session.acceptFace(front, token: nextToken))
        XCTAssertFalse(try session.acceptFace(front, token: nextToken))
        XCTAssertEqual(session.captures.count, 1)
    }

    func testCorrectionAlwaysRevalidatesAndGatesReadiness() throws {
        let session = AppSession()
        session.start(.solve)
        try scanSolvedCube(into: session)
        try session.validateCurrentCube()
        try session.correctSticker(at: 0, color: .red)
        XCTAssertEqual(session.phase, .requiresCorrection)
        XCTAssertFalse(session.validation!.isValid)
        XCTAssertThrowsError(try session.beginSolutionCalculation())
        try session.correctSticker(at: 0, color: .white)
        XCTAssertEqual(session.phase, .cubeReady)
        XCTAssertTrue(session.validation!.isValid)
    }

    func testStaleTokensAfterLeaveAndRestartAreIgnored() throws {
        let session = AppSession()
        session.start(.solve)
        let old = try session.beginFaceProcessing()
        session.leave()
        session.start(.learn)
        let current = try session.beginFaceProcessing()
        let capture = CapturedFace(face: .front, imageFace: try CubeState.solved()[.front], rotationToCanonical: .none)
        XCTAssertFalse(try session.acceptFace(capture, token: old))
        session.rejectFace(token: old)
        XCTAssertEqual(session.phase, .processingFace)
        XCTAssertNil(session.errorMessage)
        XCTAssertTrue(try session.acceptFace(capture, token: current))
    }

    func testUncooperativeAsyncCaptureCannotOverwriteNewSession() async throws {
        let session = AppSession()
        let oldGate = CaptureGate()
        let newGate = CaptureGate()
        let capture = CapturedFace(face: .front, imageFace: try CubeState.solved()[.front], rotationToCanonical: .none)
        session.start(.solve)
        let oldTask = try session.processFace { await oldGate.value() }
        await oldGate.waitUntilEntered()
        session.rescan()
        let newTask = try session.processFace { await newGate.value() }
        await newGate.waitUntilEntered()
        await oldGate.resolve(capture)
        await oldTask.value
        XCTAssertTrue(oldTask.isCancelled)
        XCTAssertEqual(session.phase, .processingFace)
        XCTAssertTrue(session.captures.isEmpty)
        XCTAssertNil(session.errorMessage)
        await newGate.resolve(capture)
        await newTask.value
        XCTAssertEqual(session.phase, .awaitingNextFace)
        XCTAssertEqual(session.captures.count, 1)
    }

    func testAsyncCaptureFailureCanBeRetried() async throws {
        let session = AppSession()
        session.start(.solve)
        let task = try session.processFace { throw CancellationError() }
        await task.value
        XCTAssertEqual(session.phase, .scanning)
        XCTAssertNotNil(session.errorMessage)
        let capture = CapturedFace(face: .front, imageFace: try CubeState.solved()[.front], rotationToCanonical: .none)
        let retry = try session.processFace { capture }
        await retry.value
        XCTAssertEqual(session.phase, .awaitingNextFace)
        XCTAssertNil(session.errorMessage)
    }

    private func scanSolvedCube(into session: AppSession) throws {
        let cube = try CubeState.solved()
        for (index, face) in CaptureAssembly.sequence.enumerated() {
            XCTAssertEqual(session.nextFace, face)
            let token = try session.beginFaceProcessing()
            XCTAssertTrue(try session.acceptFace(CapturedFace(face: face, imageFace: cube[face], rotationToCanonical: .none), token: token))
            if index < 5 {
                XCTAssertEqual(session.phase, .awaitingNextFace)
                try session.continueScanning()
            }
        }
    }
}

private actor CaptureGate {
    private var continuation: CheckedContinuation<CapturedFace, Never>?
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []

    func value() async -> CapturedFace {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            entryWaiters.forEach { $0.resume() }
            entryWaiters = []
        }
    }

    func waitUntilEntered() async {
        if continuation != nil { return }
        await withCheckedContinuation { entryWaiters.append($0) }
    }

    func resolve(_ capture: CapturedFace) {
        continuation?.resume(returning: capture)
        continuation = nil
    }
}
