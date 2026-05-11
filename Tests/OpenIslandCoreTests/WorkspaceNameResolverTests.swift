import Foundation
import Testing
@testable import OpenIslandCore

struct WorkspaceNameResolverTests {
    @Test
    func gitBranchReadsNormalRepositoryHead() throws {
        let repo = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repo) }

        let git = repo.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: git, withIntermediateDirectories: true)
        try "ref: refs/heads/feat/v8-engineering\n".write(
            to: git.appendingPathComponent("HEAD"),
            atomically: true,
            encoding: .utf8
        )

        #expect(WorkspaceNameResolver.gitBranch(for: repo.path) == "feat/v8-engineering")
    }

    @Test
    func gitBranchReadsGitdirFileForWorktree() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let worktree = root.appendingPathComponent("worktree")
        let gitdir = root.appendingPathComponent("repo.git/worktrees/feature")
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: gitdir, withIntermediateDirectories: true)
        try "gitdir: \(gitdir.path)\n".write(
            to: worktree.appendingPathComponent(".git"),
            atomically: true,
            encoding: .utf8
        )
        try "ref: refs/heads/feature/ui\n".write(
            to: gitdir.appendingPathComponent("HEAD"),
            atomically: true,
            encoding: .utf8
        )

        #expect(WorkspaceNameResolver.gitBranch(for: worktree.path) == "feature/ui")
    }

    @Test
    func gitBranchPrefersClaudeWorktreePathBranch() throws {
        let cwd = "/tmp/open-island/.claude/worktrees/feat+v8-design"

        #expect(WorkspaceNameResolver.gitBranch(for: cwd) == "feat/v8-design")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspaceNameResolverTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
