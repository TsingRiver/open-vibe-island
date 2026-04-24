import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

@MainActor
struct CodexAppServerCoordinatorTests {
    @Test
    func notLoadedStatusMarksCodexThreadAsEnded() {
        let coordinator = CodexAppServerCoordinator()
        var events: [AgentEvent] = []
        coordinator.onEvent = { events.append($0) }

        coordinator.handleNotification(
            .threadStatusChanged(
                threadId: "codex-thread-1",
                status: CodexThreadStatus(type: .notLoaded, activeFlags: nil)
            )
        )

        #expect(events.count == 1)

        guard case let .sessionCompleted(payload) = events[0] else {
            Issue.record("Expected notLoaded Codex thread to emit sessionCompleted")
            return
        }

        #expect(payload.sessionID == "codex-thread-1")
        #expect(payload.summary == "Codex thread unloaded.")
        #expect(payload.isSessionEnd == true)
    }

    @Test
    func idleStatusKeepsCodexThreadCompletedButOpen() {
        let coordinator = CodexAppServerCoordinator()
        var events: [AgentEvent] = []
        coordinator.onEvent = { events.append($0) }

        coordinator.handleNotification(
            .threadStatusChanged(
                threadId: "codex-thread-2",
                status: CodexThreadStatus(type: .idle, activeFlags: nil)
            )
        )

        #expect(events.count == 1)

        guard case let .activityUpdated(payload) = events[0] else {
            Issue.record("Expected idle Codex thread to emit activityUpdated")
            return
        }

        #expect(payload.sessionID == "codex-thread-2")
        #expect(payload.summary == "Idle.")
        #expect(payload.phase == .completed)
    }

    /// Verifies that a normal app-server turn completion uses the same
    /// turn-level completion event as hook-based Stop without closing the
    /// Codex thread.
    @Test
    func completedTurnEmitsTurnLevelCompletionWithoutEndingThread() {
        let coordinator = CodexAppServerCoordinator()
        var events: [AgentEvent] = []
        coordinator.onEvent = { events.append($0) }

        coordinator.handleNotification(
            .turnCompleted(
                threadId: "codex-thread-3",
                turn: CodexTurn(id: "turn-1", status: .completed)
            )
        )

        #expect(events.count == 1)

        guard case let .sessionCompleted(payload) = events[0] else {
            Issue.record("Expected completed Codex turn to emit sessionCompleted")
            return
        }

        #expect(payload.sessionID == "codex-thread-3")
        #expect(payload.summary == "Turn completed.")
        #expect(payload.isInterrupt == false)
        #expect(payload.isSessionEnd != true)
    }

    /// Verifies that a user-initiated Codex app-server interruption is
    /// surfaced as an interrupt completion so running state is cleared without
    /// showing a normal completion notification.
    @Test
    func interruptedTurnEmitsInterruptCompletion() {
        let coordinator = CodexAppServerCoordinator()
        var events: [AgentEvent] = []
        coordinator.onEvent = { events.append($0) }

        coordinator.handleNotification(
            .turnCompleted(
                threadId: "codex-thread-4",
                turn: CodexTurn(id: "turn-2", status: .interrupted)
            )
        )

        #expect(events.count == 1)

        guard case let .sessionCompleted(payload) = events[0] else {
            Issue.record("Expected interrupted Codex turn to emit sessionCompleted")
            return
        }

        #expect(payload.sessionID == "codex-thread-4")
        #expect(payload.summary == "Turn interrupted.")
        #expect(payload.isInterrupt == true)
        #expect(payload.isSessionEnd != true)
    }
}
