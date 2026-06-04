import Foundation

/// Plans how a locally built development bundle may safely refresh its source checkout.
struct DevelopmentBuildSyncPlan: Equatable {
    enum Action: Equatable {
        case rebuildOnly
        case mergeAndRebuild
        case blocked(String)
    }

    /// Returns whether the git status output only contains tolerated local noise.
    /// - Parameter statusOutput: Raw `git status --porcelain` output.
    /// - Returns: `true` when the workspace is clean apart from `.swiftpm`.
    static func hasOnlyAllowedWorkspaceNoise(_ statusOutput: String) -> Bool {
        for line in statusOutput.split(whereSeparator: \.isNewline) {
            let entry = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !entry.isEmpty else {
                continue
            }

            guard entry.hasPrefix("?? ") else {
                return false
            }

            let path = String(entry.dropFirst(3))
            if path == ".swiftpm/" || path.hasPrefix(".swiftpm/") {
                continue
            }

            return false
        }

        return true
    }

    /// Parses `git rev-list --left-right --count HEAD...origin/main` output.
    /// - Parameter output: The raw command output containing ahead / behind counts.
    /// - Returns: Parsed counts when the output is well-formed.
    static func parseAheadBehindCounts(_ output: String) -> (ahead: Int, behind: Int)? {
        let parts = output.split(whereSeparator: \.isWhitespace)
        guard parts.count == 2,
              let ahead = Int(parts[0]),
              let behind = Int(parts[1]) else {
            return nil
        }

        return (ahead, behind)
    }

    /// Chooses the safest repo-sync action for the current development checkout.
    /// - Parameters:
    ///   - statusOutput: Raw `git status --porcelain` output.
    ///   - aheadCount: Commits present only in `HEAD`.
    ///   - behindCount: Commits present only in `origin/main`.
    /// - Returns: The action that preserves local work while still refreshing the dev bundle.
    static func action(
        statusOutput: String,
        aheadCount: Int,
        behindCount: Int
    ) -> Action {
        guard hasOnlyAllowedWorkspaceNoise(statusOutput) else {
            return .blocked("Dev sync skipped: the repository has local changes.")
        }

        if behindCount > 0 {
            return .mergeAndRebuild
        }

        return .rebuildOnly
    }
}

/// Safely refreshes the local checkout and relaunches `Open Island Dev.app` when a newer appcast version exists.
@MainActor
final class DevelopmentBuildSyncCoordinator {
    /// Receives human-readable status updates suitable for `AppModel.lastActionMessage`.
    var onStatusMessage: ((String) -> Void)?

    private var syncTask: Task<Void, Never>?
    private var isSyncInProgress = false

    /// Starts a guarded repo refresh for the detected appcast version.
    /// - Parameter targetVersion: The newer appcast version Sparkle discovered.
    func syncToLatestIfPossible(targetVersion: String) {
        guard !isSyncInProgress else {
            return
        }

        guard let repoRoot = Self.developmentRepoRoot() else {
            return
        }

        isSyncInProgress = true
        onStatusMessage?("检测到 Open Island 新版本 \(targetVersion)。正在同步本地仓库并重新构建 Open Island Dev…")

        syncTask = Task.detached(priority: .utility) {
            let message = await Self.performSync(targetVersion: targetVersion, repoRoot: repoRoot)
            await MainActor.run {
                self.isSyncInProgress = false
                self.onStatusMessage?(message)
            }
        }
    }

    /// Performs the actual git / rebuild workflow off the main actor.
    /// - Parameters:
    ///   - targetVersion: The newer appcast version Sparkle discovered.
    ///   - repoRoot: The source checkout embedded into the dev bundle metadata.
    /// - Returns: A user-facing status message describing the outcome.
    private static func performSync(targetVersion: String, repoRoot: URL) async -> String {
        do {
            let statusResult = try runCommand(
                executablePath: "/usr/bin/env",
                arguments: ["git", "status", "--porcelain"],
                currentDirectoryURL: repoRoot
            )
            guard statusResult.exitCode == 0 else {
                return commandFailureMessage(
                    action: "检查 Git 状态",
                    result: statusResult
                )
            }

            let fetchResult = try runCommand(
                executablePath: "/usr/bin/env",
                arguments: ["git", "fetch", "origin"],
                currentDirectoryURL: repoRoot
            )
            guard fetchResult.exitCode == 0 else {
                return commandFailureMessage(
                    action: "拉取 origin/main",
                    result: fetchResult
                )
            }

            let aheadBehindResult = try runCommand(
                executablePath: "/usr/bin/env",
                arguments: ["git", "rev-list", "--left-right", "--count", "HEAD...origin/main"],
                currentDirectoryURL: repoRoot
            )
            guard aheadBehindResult.exitCode == 0 else {
                return commandFailureMessage(
                    action: "读取 Ahead/Behind 提交计数",
                    result: aheadBehindResult
                )
            }

            guard let counts = DevelopmentBuildSyncPlan.parseAheadBehindCounts(aheadBehindResult.stdout) else {
                return "开发版同步已跳过：无法解析 Git 的 Ahead/Behind 提交计数。"
            }

            let action = DevelopmentBuildSyncPlan.action(
                statusOutput: statusResult.stdout,
                aheadCount: counts.ahead,
                behindCount: counts.behind
            )

            switch action {
            case .blocked(let reason):
                return reason
            case .mergeAndRebuild:
                let mergeResult = try runCommand(
                    executablePath: "/usr/bin/env",
                    arguments: ["git", "merge", "origin/main", "--no-edit"],
                    currentDirectoryURL: repoRoot
                )
                if mergeResult.exitCode != 0 {
                    // 合并发生冲突，自动执行 --abort 还原工作区，防止仓库处于合并中的紊乱状态
                    _ = try? runCommand(
                        executablePath: "/usr/bin/env",
                        arguments: ["git", "merge", "--abort"],
                        currentDirectoryURL: repoRoot
                    )
                    return "开发版同步已跳过：合并 origin/main 时检测到冲突。已自动放弃合并以还原工作区。"
                }
            case .rebuildOnly:
                break
            }

            try launchRebuildScript(repoRoot: repoRoot)
            return "检测到 Open Island 新版本 \(targetVersion)。正在从最新的仓库代码重新构建 Open Island Dev…"
        } catch {
            return "开发版同步失败：\(error.localizedDescription)"
        }
    }

    /// Reads the development checkout root embedded into the generated dev bundle.
    /// - Returns: The checkout URL when the app is running from `Open Island Dev.app`.
    private static func developmentRepoRoot() -> URL? {
        guard let path = Bundle.main.object(
            forInfoDictionaryKey: "OpenIslandDevelopmentRepoRoot"
        ) as? String,
        !path.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Runs a command and captures both stdout and stderr for diagnostics.
    /// - Parameters:
    ///   - executablePath: Absolute path to the executable.
    ///   - arguments: Command-line arguments passed to the executable.
    ///   - currentDirectoryURL: Working directory for the command.
    /// - Returns: Exit code plus decoded stdout / stderr text.
    private static func runCommand(
        executablePath: String,
        arguments: [String],
        currentDirectoryURL: URL
    ) throws -> (exitCode: Int32, stdout: String, stderr: String) {
        let task = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        task.executableURL = URL(fileURLWithPath: executablePath)
        task.arguments = arguments
        task.currentDirectoryURL = currentDirectoryURL
        task.standardOutput = stdoutPipe
        task.standardError = stderrPipe

        try task.run()
        task.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return (
            exitCode: task.terminationStatus,
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrData, as: UTF8.self)
        )
    }

    /// Launches the existing dev rebuild script from the checkout root.
    /// - Parameter repoRoot: The source checkout embedded into the dev bundle metadata.
    private static func launchRebuildScript(repoRoot: URL) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["scripts/launch-dev-app.sh", "--skip-setup"]
        task.currentDirectoryURL = repoRoot
        try task.run()
    }

    /// Formats a concise git-command failure message for the UI status bar.
    /// - Parameters:
    ///   - action: The user-facing description of the failed step.
    ///   - result: Exit code plus captured stdout / stderr output.
    /// - Returns: A single-line failure description.
    private static func commandFailureMessage(
        action: String,
        result: (exitCode: Int32, stdout: String, stderr: String)
    ) -> String {
        let detail = [result.stderr, result.stdout]
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if detail.isEmpty {
            return "开发版同步失败，在执行“\(action)”时发生错误 (退出码 \(result.exitCode))。"
        }

        return "开发版同步失败，在执行“\(action)”时发生错误：\(detail)"
    }
}
