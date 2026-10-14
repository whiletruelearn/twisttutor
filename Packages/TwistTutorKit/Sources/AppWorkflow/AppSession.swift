import CubeCore
import CubeValidation
import CubeSolver
import Foundation
import Observation

public enum ExperienceMode: Sendable { case solve, learn }

public enum WorkflowPhase: Equatable, Sendable {
    case idle, scanning, processingFace, awaitingNextFace, validatingCube, requiresCorrection
    case cubeReady, calculatingSolution, solving, teaching, completed
}

public enum WorkflowError: Error, Equatable, Sendable {
    case unexpectedPhase(WorkflowPhase)
    case unexpectedFace(expected: CubeFaceID, actual: CubeFaceID)
    case cubeNotReady
    case wrongExperienceMode
}

/// Camera hardware state is owned by the capture adapter, not by the cube workflow.
public enum CameraLifecycle: Equatable, Sendable {
    case stopped, requestingPermission, running, interrupted, permissionDenied
}

/// Token identity rejects results from work that ignored cooperative Task cancellation.
public struct OperationToken: Equatable, Sendable {
    fileprivate let id = UUID()
}

@MainActor @Observable
public final class AppSession {
    public private(set) var phase: WorkflowPhase = .idle
    public private(set) var mode: ExperienceMode = .solve
    public private(set) var captures: [CapturedFace] = []
    public private(set) var cube: CubeState?
    public private(set) var validation: ValidationReport?
    public private(set) var errorMessage: String?
    public private(set) var solution: VerifiedSolution?
    @ObservationIgnored private var activeOperation: OperationToken?
    @ObservationIgnored private var pendingTask: Task<Void, Never>?
    @ObservationIgnored private var pendingTaskToken: OperationToken?

    public init() {}

    public var nextFace: CubeFaceID? {
        captures.count < CaptureAssembly.sequence.count ? CaptureAssembly.sequence[captures.count] : nil
    }

    public func start(_ mode: ExperienceMode) {
        cancelPendingWork()
        self.mode = mode
        captures = []; cube = nil; validation = nil; errorMessage = nil; solution = nil
        phase = .scanning
    }

    /// Leaving a flow invalidates all outstanding results, including uncooperative adapters.
    public func leave() {
        cancelPendingWork()
        captures = []; cube = nil; validation = nil; errorMessage = nil; solution = nil
        phase = .idle
    }

    public func rescan() { start(mode) }

    public func beginFaceProcessing() throws -> OperationToken {
        guard phase == .scanning else { throw WorkflowError.unexpectedPhase(phase) }
        let token = newOperation()
        errorMessage = nil
        phase = .processingFace
        return token
    }

    /// Returns false for stale/duplicate completions, without modifying current session state.
    @discardableResult
    public func acceptFace(_ capture: CapturedFace, token: OperationToken) throws -> Bool {
        guard token == activeOperation, phase == .processingFace else { return false }
        guard let expected = nextFace else { throw WorkflowError.unexpectedPhase(phase) }
        guard capture.face == expected else { throw WorkflowError.unexpectedFace(expected: expected, actual: capture.face) }
        captures.append(capture)
        activeOperation = nil
        if captures.count == 6 {
            cube = try CaptureAssembly.assemble(captures)
            phase = .validatingCube
        } else {
            phase = .awaitingNextFace
        }
        return true
    }

    public func continueScanning() throws {
        guard phase == .awaitingNextFace else { throw WorkflowError.unexpectedPhase(phase) }
        phase = .scanning
    }

    /// An adapter supplies image processing; the session handles lifecycle and stale results only.
    @discardableResult
    public func processFace(using operation: @escaping @Sendable () async throws -> CapturedFace) throws -> Task<Void, Never> {
        let token = try beginFaceProcessing()
        pendingTaskToken = token
        let task = Task { [weak self] in
            do {
                let capture = try await operation()
                try Task.checkCancellation()
                guard let self else { return }
                _ = try self.acceptFace(capture, token: token)
            } catch {
                self?.rejectFace(token: token)
            }
            guard let self, self.pendingTaskToken == token else { return }
            self.pendingTask = nil
            self.pendingTaskToken = nil
        }
        pendingTask = task
        return task
    }

    public func rejectFace(token: OperationToken) {
        guard activeOperation == token, phase == .processingFace else { return }
        activeOperation = nil
        phase = .scanning
        errorMessage = "We couldn't read this face. Please try again."
    }

    public func waitForPendingOperation() async { await pendingTask?.value }

    /// The current cube is always validated locally; callers cannot inject a successful report.
    public func validateCurrentCube() throws {
        guard phase == .validatingCube || phase == .requiresCorrection else { throw WorkflowError.unexpectedPhase(phase) }
        guard let cube else { throw WorkflowError.cubeNotReady }
        let result = CubeValidator.validate(cube)
        validation = result
        phase = result.isValid ? .cubeReady : .requiresCorrection
    }

    public func correctSticker(at index: Int, color: CubeColorID) throws {
        guard phase == .requiresCorrection || phase == .cubeReady else { throw WorkflowError.unexpectedPhase(phase) }
        guard let cube else { throw WorkflowError.cubeNotReady }
        self.cube = try cube.replacingColor(at: index, with: color)
        solution = nil
        phase = .validatingCube
        try validateCurrentCube()
    }

    public func beginSolutionCalculation() throws -> OperationToken {
        guard phase == .cubeReady else { throw WorkflowError.unexpectedPhase(phase) }
        guard mode == .solve else { throw WorkflowError.wrongExperienceMode }
        let token = newOperation()
        solution = nil
        errorMessage = nil
        phase = .calculatingSolution
        return token
    }

    /// The verifier binds the moves to an immutable snapshot, not just a success flag.
    @discardableResult
    public func finishSolutionCalculation(token: OperationToken, solution: VerifiedSolution) throws -> Bool {
        guard activeOperation == token, phase == .calculatingSolution else { return false }
        guard solution.initialCube == cube else { throw SolverError.resultForDifferentCube }
        activeOperation = nil
        self.solution = solution
        phase = .solving
        errorMessage = nil
        return true
    }

    public func failSolutionCalculation(token: OperationToken) {
        guard activeOperation == token, phase == .calculatingSolution else { return }
        activeOperation = nil
        solution = nil
        phase = .cubeReady
        errorMessage = "We couldn't find a verified solution. Please try again."
    }

    public func cancelSolutionCalculation() {
        guard phase == .calculatingSolution else { return }
        cancelPendingWork()
        solution = nil
        errorMessage = nil
        phase = .cubeReady
    }

    @discardableResult
    public func calculateSolution(using solver: any CubeSolving = QuickSolver()) throws -> Task<Void, Never> {
        guard let cube else { throw WorkflowError.cubeNotReady }
        let token = try beginSolutionCalculation()
        pendingTaskToken = token
        let task = Task { [weak self] in
            do {
                let result = try await solver.solve(cube)
                try Task.checkCancellation()
                _ = try self?.finishSolutionCalculation(token: token, solution: result)
            } catch {
                self?.failSolutionCalculation(token: token)
            }
            guard let self, self.pendingTaskToken == token else { return }
            self.pendingTask = nil
            self.pendingTaskToken = nil
        }
        pendingTask = task
        return task
    }

    public func beginTeaching() throws {
        guard phase == .cubeReady else { throw WorkflowError.unexpectedPhase(phase) }
        guard mode == .learn else { throw WorkflowError.wrongExperienceMode }
        phase = .teaching
    }

    public func complete() throws {
        guard phase == .solving || phase == .teaching else { throw WorkflowError.unexpectedPhase(phase) }
        phase = .completed
    }

    private func newOperation() -> OperationToken {
        cancelPendingWork()
        let token = OperationToken()
        activeOperation = token
        return token
    }

    private func cancelPendingWork() {
        activeOperation = nil
        pendingTask?.cancel()
        pendingTask = nil
        pendingTaskToken = nil
    }
}
