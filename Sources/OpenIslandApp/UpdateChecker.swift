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

    /// Fires only for the locally generated dev bundle when a newer appcast item is found.
    @ObservationIgnored
    var onDevelopmentUpdateDetected: ((String) -> Void)?

    /// Fires only for the locally generated dev bundle when checking for updates is manually triggered.
    @ObservationIgnored
    var onCheckingForUpdates: (() -> Void)?

    /// Fires only for the locally generated dev bundle when no newer appcast item is found.
    @ObservationIgnored
    var onDevelopmentNoUpdateDetected: (() -> Void)?

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
            }

        #if DEBUG
        startDevelopmentPolling()
        #endif
    }

    /// Manually trigger an update check (from Settings UI).
    func checkForUpdates() {
        #if DEBUG
        guard isDevelopmentBundle else {
            return
        }
        // 触发开始检查的回调以在界面上显示“正在检查更新…”
        onCheckingForUpdates?()
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
                self.onDevelopmentUpdateDetected?(version)
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
                // 触发无更新的回调以在界面上显示“已是最新版本”
                self.onDevelopmentNoUpdateDetected?()
            }
            #endif
        }
    }
}
