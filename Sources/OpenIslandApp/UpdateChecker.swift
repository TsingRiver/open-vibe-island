import Combine
import Foundation
import Sparkle

/// Wraps Sparkle's `SPUUpdater` to provide observable update state for SwiftUI.
///
/// Sparkle handles the full lifecycle: checking for updates, downloading,
/// extracting, replacing the app bundle, and relaunching.
/// This wrapper simply exposes the current state so the UI can react.
@MainActor
@Observable
final class UpdateChecker: NSObject {
    static let releasesURL = URL(string: "https://github.com/Octane0411/open-vibe-island/releases")!

    private(set) var canCheckForUpdates = false
    private(set) var hasUpdate = false
    private(set) var latestVersion: String?

    /// 跟踪上一次自动检查更新的时间，确保一天最多自动触发一次
    @ObservationIgnored
    private var lastAutoCheckDate: Date? {
        get {
            UserDefaults.standard.object(forKey: "OpenIslandLastAutoCheckUpdateDate") as? Date
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "OpenIslandLastAutoCheckUpdateDate")
        }
    }

    /// 标记当前正在执行的检查更新是否为用户手动点击触发
    @ObservationIgnored
    private var isCurrentlyCheckingUserInitiated = false

    /// Fires only for the locally generated dev bundle when a newer appcast item is found.
    @ObservationIgnored
    var onDevelopmentUpdateDetected: ((String, Bool) -> Void)?

    /// Fires only for the locally generated dev bundle when checking for updates is manually triggered.
    @ObservationIgnored
    var onCheckingForUpdates: ((Bool) -> Void)?

    /// Fires only for the locally generated dev bundle when no newer appcast item is found.
    @ObservationIgnored
    var onDevelopmentNoUpdateDetected: ((Bool) -> Void)?

    @ObservationIgnored
    private var updaterController: SPUStandardUpdaterController!

    @ObservationIgnored
    private var cancellable: AnyCancellable?

    @ObservationIgnored
    private var developmentPollingTask: Task<Void, Never>?

    @ObservationIgnored
    private var hasStartedUpdater = false

    override init() {
        super.init()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    /// Start Sparkle's automatic update checking schedule.
    /// Call once after app launch.
    func startIfNeeded() {
        guard !hasStartedUpdater else {
            return
        }

        #if DEBUG
        guard isDevelopmentBundle else {
            // Unit tests and non-dev debug launches do not carry the custom
            // bundle metadata required for guarded repo sync. Keep their
            // previous no-op behavior.
            print("[UpdateChecker] skipped in DEBUG build without development bundle metadata")
            return
        }
        #endif

        hasStartedUpdater = true

        let updater = updaterController.updater
        updater.automaticallyDownloadsUpdates = false
        #if DEBUG
        updater.automaticallyChecksForUpdates = false
        #else
        updater.automaticallyChecksForUpdates = true
        updater.updateCheckInterval = 60 * 60 // 1 hour
        #endif

        do {
            try updater.start()
        } catch {
            print("[UpdateChecker] Failed to start Sparkle updater: \(error)")
        }

        cancellable = updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.canCheckForUpdates = value
            }    }

    /// Manually or automatically trigger an update check (from Settings UI).
    /// - Parameter isUserInitiated: `true` when triggered via manual button click, `false` for automatic load checks.
    func checkForUpdates(isUserInitiated: Bool = true) {
        #if DEBUG
        guard isDevelopmentBundle else {
            return
        }

        if !isUserInitiated {
            // 如果是自动检查更新，一天最多自动触发一次，超出 24 小时才继续
            if let lastCheck = lastAutoCheckDate, Date().timeIntervalSince(lastCheck) < 24 * 60 * 60 {
                return
            }
            lastAutoCheckDate = Date()
        }

        isCurrentlyCheckingUserInitiated = isUserInitiated
        // 触发开始检查的回调以在界面上显示“正在检查更新…”
        onCheckingForUpdates?(isUserInitiated)
        updaterController.updater.checkForUpdateInformation()
        #else
        updaterController.checkForUpdates(nil)
        #endif
    }

    /// Returns `true` only for the generated dev bundle that embeds its checkout root.
    private var isDevelopmentBundle: Bool {
        Bundle.main.object(forInfoDictionaryKey: "OpenIslandDevelopmentRepoRoot") as? String != nil
    }

    /// Starts background informational probes so the dev bundle can detect new appcast versions
    /// without letting Sparkle replace the checkout-built app with a release zip.
    private func startDevelopmentPolling() {
        guard developmentPollingTask == nil else {
            return
        }

        developmentPollingTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else {
                return
            }

            self.probeForDevelopmentUpdates()

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60 * 60))
                guard !Task.isCancelled else {
                    return
                }

                self.probeForDevelopmentUpdates()
            }
        }
    }

    /// Runs a non-installing Sparkle probe for the dev bundle.
    private func probeForDevelopmentUpdates() {
        let updater = updaterController.updater
        guard updater.canCheckForUpdates else {
            return
        }

        updater.checkForUpdateInformation()
    }
}

// MARK: - SPUUpdaterDelegate

extension UpdateChecker: SPUUpdaterDelegate {
    nonisolated func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        Set()
    }

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        Task { @MainActor in
            self.hasUpdate = true
            self.latestVersion = version
            #if DEBUG
            if self.isDevelopmentBundle {
                let isUser = self.isCurrentlyCheckingUserInitiated
                self.isCurrentlyCheckingUserInitiated = false
                self.onDevelopmentUpdateDetected?(version, isUser)
            }
            #endif
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        Task { @MainActor in
            self.hasUpdate = false
            self.latestVersion = nil
            #if DEBUG
            if self.isDevelopmentBundle {
                let isUser = self.isCurrentlyCheckingUserInitiated
                self.isCurrentlyCheckingUserInitiated = false
                // 触发无更新的回调以在界面上显示“已是最新版本”
                self.onDevelopmentNoUpdateDetected?(isUser)
            }
            #endif
        }
    }
}
