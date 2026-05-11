import Testing
@testable import OpenIslandApp
import OpenIslandCore

@MainActor
struct ProcessMonitoringCoordinatorTests {
    @Test
    func reconcileNotifiesObservedCodexCLISessionIDsEvenWhenStateIsEmpty() {
        let coordinator = ProcessMonitoringCoordinator()
        var observedIDs: Set<String>?
        coordinator.stateAccessor = { SessionState() }
        coordinator.stateUpdater = { _ in }
        coordinator.onCodexCLIProcessesObserved = { ids in
            observedIDs = ids
        }

        coordinator.reconcileSessionAttachments(activeProcesses: [
            ActiveProcessSnapshot(
                tool: .codex,
                sessionID: "019e0dc1-3f8b-7eb0-ae8d-04a5911e95b9",
                workingDirectory: "/tmp/open-island",
                terminalTTY: "/dev/ttys001",
                terminalApp: "Ghostty"
            ),
        ])

        #expect(observedIDs == Set(["019e0dc1-3f8b-7eb0-ae8d-04a5911e95b9"]))
    }
}
