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
}
