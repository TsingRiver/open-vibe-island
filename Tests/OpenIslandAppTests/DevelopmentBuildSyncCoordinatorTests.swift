import Testing
@testable import OpenIslandApp

struct DevelopmentBuildSyncCoordinatorTests {
    @Test
    func allowsOnlySwiftPMWorkspaceNoise() {
        let statusOutput = """
        ?? .swiftpm/
        ?? .swiftpm/xcode/package.xcworkspace/
        """

        #expect(DevelopmentBuildSyncPlan.hasOnlyAllowedWorkspaceNoise(statusOutput))
    }

    @Test
    func blocksTrackedWorkspaceChanges() {
        let statusOutput = """
         M Sources/OpenIslandApp/UpdateChecker.swift
        """

        #expect(!DevelopmentBuildSyncPlan.hasOnlyAllowedWorkspaceNoise(statusOutput))
    }

    @Test
    func parsesAheadBehindCounts() {
        let counts = DevelopmentBuildSyncPlan.parseAheadBehindCounts("7\t0\n")
        #expect(counts?.ahead == 7)
        #expect(counts?.behind == 0)
    }

    @Test
    func choosesFastForwardWhenOnlyBehindOriginMain() {
        let action = DevelopmentBuildSyncPlan.action(
            statusOutput: "",
            aheadCount: 0,
            behindCount: 3
        )

        #expect(action == .fastForwardAndRebuild)
    }

    @Test
    func choosesRebuildOnlyWhenCheckoutAlreadyContainsLatestCode() {
        let action = DevelopmentBuildSyncPlan.action(
            statusOutput: "?? .swiftpm/\n",
            aheadCount: 4,
            behindCount: 0
        )

        #expect(action == .rebuildOnly)
    }

    @Test
    func blocksDivergedBranchHistory() {
        let action = DevelopmentBuildSyncPlan.action(
            statusOutput: "",
            aheadCount: 2,
            behindCount: 1
        )

        #expect(action == .blocked("Dev sync skipped: the current branch diverged from origin/main."))
    }
}
