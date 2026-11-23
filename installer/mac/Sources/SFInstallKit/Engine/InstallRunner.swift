import Foundation

public struct LogLine: Sendable, Hashable, Identifiable {
    public enum Level: String, Sendable { case info, command, success, warning, error, planned }
    public var id = UUID()
    public var time: Date
    public var level: Level
    public var text: String
    public init(time: Date = Date(), level: Level, text: String) { self.time = time; self.level = level; self.text = text }
}

public enum RollbackStepState: String, Sendable { case running, done, skipped, failed }

public enum InstallEvent: Sendable {
    case stepStarted(index: Int)
    case progress(index: Int, fraction: Double, detail: String)
    case log(LogLine)
    case stepCompleted(index: Int)
    case failed(index: Int, message: String)
    case rollbackStarted(steps: [Int])
    case rollbackStep(index: Int, state: RollbackStepState)
    case rollbackFinished(clean: Bool)
    case finished(DiskSnapshot)
    case cancelled
    /// Stopped after a failure without undoing anything (autoRollback off); undo with `rollback`.
    case stopped(Checkpoint, failedIndex: Int)
}

/// Runs a plan step by step against a backend, journaling every command and checkpointing after
/// each step. On failure or cancellation it undoes completed steps in reverse order.
public actor InstallRunner {
    public let backend: any DiskBackend
    public let journal: Journal
    private var cancelRequested = false
    private var checkpoint = Checkpoint()

    public init(backend: any DiskBackend, journal: Journal) {
        self.backend = backend
        self.journal = journal
    }

    /// Asks the runner to stop at the next operation boundary and roll back.
    public func cancel() { cancelRequested = true }

    /// Starts (or resumes, from `resume`) a plan. Events arrive in order; the stream ends after
    /// `.finished`, `.rollbackFinished` or `.cancelled`.
    public nonisolated func run(_ plan: InstallPlan, resume: Checkpoint? = nil, autoRollback: Bool = true) -> AsyncStream<InstallEvent> {
        AsyncStream { continuation in
            let task = Task { await self.execute(plan, resume: resume, autoRollback: autoRollback, emit: { continuation.yield($0) }); continuation.finish() }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Undoes what a stopped run left behind ("Undo Changes", UX-FLOW E2 → E3).
    public nonisolated func rollback(_ plan: InstallPlan, from checkpoint: Checkpoint, failedIndex: Int?) -> AsyncStream<InstallEvent> {
        AsyncStream { continuation in
            let task = Task {
                await self.setCheckpoint(checkpoint)
                await self.rollback(plan, failedIndex: failedIndex, emit: { continuation.yield($0) })
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func setCheckpoint(_ c: Checkpoint) { checkpoint = c }

    private func execute(_ plan: InstallPlan, resume: Checkpoint?, autoRollback: Bool, emit: @Sendable (InstallEvent) -> Void) async {
        checkpoint = resume ?? Checkpoint()
        let dry = backend.kind == .simulated
        if resume == nil {
            await journal.append(.init(event: .planned, message: "\(plan.kind.rawValue) plan for \(plan.profileID) on \(plan.disk) (\(backend.kind.rawValue))", plan: plan))
            if let snap = try? await backend.snapshot() {
                await journal.append(.init(event: .partitionTable, message: "Layout before changes", snapshot: snap))
            }
        } else {
            await journal.append(.init(event: .note, message: "Resuming after \(checkpoint.completed.map(\.rawValue).joined(separator: ", "))"))
        }

        for (index, step) in plan.steps.enumerated() where !checkpoint.completed.contains(step.id) {
            if cancelRequested || Task.isCancelled {
                await rollback(plan, failedIndex: nil, emit: emit)
                emit(.cancelled)
                return
            }
            emit(.stepStarted(index: index))
            emit(.log(LogLine(level: .info, text: "\(step.code) \(step.title)")))
            await journal.append(.init(event: .stepStarted, step: step.id, message: step.title))
            do {
                let ops = step.operations
                if ops.isEmpty {
                    try await idle(step, index: index, emit: emit)
                }
                for (k, op) in ops.enumerated() {
                    if cancelRequested { throw BackendError.cancelled }
                    let slots = checkpoint.slots
                    let resolve: @Sendable (PartRef) -> String = { ref in ref.isSlot ? (slots[String(ref.dropFirst())] ?? ref) : ref }
                    for argv in op.commands(resolve: resolve) {
                        emit(.log(LogLine(level: dry || op.isMutating ? .command : .info, text: CommandRender.render(argv))))
                    }
                    let base = Double(k) / Double(ops.count), span = 1 / Double(ops.count)
                    let result = try await backend.perform(op, context: OperationContext(step: step.id, stepIndex: index), resolve: resolve) { f, detail in
                        emit(.progress(index: index, fraction: base + f * span, detail: detail))
                    }
                    for argv in result.commands {
                        await journal.append(.init(event: .command, step: step.id, message: op.summary, command: argv,
                                                   executed: result.executed, mutating: op.isMutating))
                    }
                    if !result.executed {
                        emit(.log(LogLine(level: .planned, text: "Planned, not executed (read-only mode)")))
                    }
                    if case .addPartition(_, let slot, _, _, _, _) = op, let id = result.createdIdentifier {
                        checkpoint.slots[slot] = id
                        emit(.log(LogLine(level: .info, text: "Created \(id)")))
                    }
                }
                checkpoint.completed.append(step.id)
                await journal.append(.init(event: .stepCompleted, step: step.id, message: step.title))
                await journal.append(.init(event: .checkpoint, step: step.id, message: "checkpoint", checkpoint: checkpoint))
                emit(.progress(index: index, fraction: 1, detail: "Done"))
                emit(.log(LogLine(level: .success, text: "✓ \(step.title)")))
                emit(.stepCompleted(index: index))
            } catch {
                let cancelled = (error as? BackendError) == .cancelled || error is CancellationError
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await journal.append(.init(event: cancelled ? .cancelled : .stepFailed, step: step.id, message: message))
                if cancelled {
                    emit(.log(LogLine(level: .warning, text: "Stopping: cancelled")))
                } else {
                    emit(.log(LogLine(level: .error, text: "✗ \(step.title): \(message)")))
                    emit(.failed(index: index, message: message))
                }
                if !autoRollback && !cancelled {
                    emit(.stopped(checkpoint, failedIndex: index))
                    return
                }
                await rollback(plan, failedIndex: index, emit: emit)
                if cancelled { emit(.cancelled) }
                return
            }
        }
        await journal.append(.init(event: .finished, message: "\(plan.kind.rawValue) finished"))
        let final = (try? await backend.snapshot()) ?? DiskSnapshot(disks: [])
        emit(.finished(final))
    }

    /// Steps with no disk operations still take a moment (reads, checks); show it honestly.
    private func idle(_ step: InstallStep, index: Int, emit: @Sendable (InstallEvent) -> Void) async throws {
        if backend.kind == .simulated {
            let snap = try await backend.snapshot()
            _ = snap
        }
        for t in 1...5 {
            if cancelRequested { throw BackendError.cancelled }
            emit(.progress(index: index, fraction: Double(t) / 5, detail: step.title))
            if backend.kind == .simulated, await (backend as? SimulatedDiskBackend)?.timeScale ?? 0 > 0 {
                try await Task.sleep(nanoseconds: 180_000_000)
            }
        }
    }

    /// Undoes completed steps newest-first (and the failed step, if it left something behind).
    private func rollback(_ plan: InstallPlan, failedIndex: Int?, emit: @Sendable (InstallEvent) -> Void) async {
        var indices = plan.steps.indices.filter { checkpoint.completed.contains(plan.steps[$0].id) }
        if let f = failedIndex, !indices.contains(f) { indices.append(f) }
        indices.sort(by: >)
        emit(.rollbackStarted(steps: indices))
        await journal.append(.init(event: .rollbackStarted, message: "Rolling back \(indices.count) step(s)"))
        emit(.log(LogLine(level: .warning, text: "Rolling back…")))
        var clean = true
        for index in indices {
            let step = plan.steps[index]
            guard step.reversible else {
                emit(.rollbackStep(index: index, state: .skipped))
                if checkpoint.completed.contains(step.id) { clean = false }
                continue
            }
            // Only undo what exists: a slot that was never created needs no undo.
            let ops = step.undo.filter { op in
                switch op {
                case .deletePartition(let ref), .deleteAPFSContainer(let ref):
                    return !ref.isSlot || checkpoint.slots[String(ref.dropFirst())] != nil
                default: return true
                }
            }
            if ops.isEmpty || (index == failedIndex && !checkpoint.completed.contains(step.id) && step.undo.allSatisfy({ if case .resizeContainer = $0 { return true }; return false }) ) {
                emit(.rollbackStep(index: index, state: .skipped))
                continue
            }
            emit(.rollbackStep(index: index, state: .running))
            do {
                for op in ops {
                    let slots = checkpoint.slots
                    let resolve: @Sendable (PartRef) -> String = { ref in ref.isSlot ? (slots[String(ref.dropFirst())] ?? ref) : ref }
                    for argv in op.commands(resolve: resolve) { emit(.log(LogLine(level: .command, text: CommandRender.render(argv)))) }
                    let r = try await backend.perform(op, context: OperationContext(step: step.id, stepIndex: index, isRollback: true), resolve: resolve) { _, _ in }
                    for argv in r.commands {
                        await journal.append(.init(event: .command, step: step.id, message: "undo: \(op.summary)", command: argv, executed: r.executed))
                    }
                    switch op {
                    case .deletePartition(let ref), .deleteAPFSContainer(let ref):
                        if ref.isSlot { checkpoint.slots.removeValue(forKey: String(ref.dropFirst())) }
                    default: break
                    }
                }
                checkpoint.completed.removeAll { $0 == step.id }
                await journal.append(.init(event: .rollbackStep, step: step.id, message: "undone", checkpoint: checkpoint))
                emit(.rollbackStep(index: index, state: .done))
                emit(.log(LogLine(level: .success, text: "↺ Undid: \(step.title)")))
            } catch {
                clean = false
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await journal.append(.init(event: .rollbackStep, step: step.id, message: "undo failed: \(message)"))
                emit(.rollbackStep(index: index, state: .failed))
                emit(.log(LogLine(level: .error, text: "Couldn’t undo \(step.title): \(message)")))
            }
        }
        await journal.append(.init(event: clean ? .rollbackCompleted : .rollbackIncomplete, message: clean ? "Rolled back cleanly" : "Rollback incomplete"))
        emit(.rollbackFinished(clean: clean))
    }
}
