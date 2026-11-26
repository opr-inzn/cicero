import Foundation
import Observation
import Sparkle

@Observable
final class Updates {
    let isAvailable = Bundle.main.bundleURL.pathExtension == "app"
    private(set) var readyVersion: String?
    var checksAutomatically: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = checksAutomatically }
    }
    var installsAutomatically: Bool {
        didSet { controller.updater.automaticallyDownloadsUpdates = installsAutomatically }
    }

    @ObservationIgnored private let delegate = UpdaterDelegate()
    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var observation: NSKeyValueObservation?
    @ObservationIgnored private var checkWhenReady = false
    @ObservationIgnored private var installReady: (() -> Void)?

    init() {
        let controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: delegate, userDriverDelegate: nil)
        self.controller = controller
        checksAutomatically = controller.updater.automaticallyChecksForUpdates
        installsAutomatically = controller.updater.automaticallyDownloadsUpdates
        delegate.onReady = { [weak self] version, install in
            self?.readyVersion = version
            self?.installReady = install
        }
        #if CICERO_DEV
        if let preview = ProcessInfo.processInfo.environment["CICERO_PREVIEW_UPDATE"], !preview.isEmpty {
            readyVersion = preview
        }
        #endif
        guard isAvailable else { return }
        controller.startUpdater()
        if checksAutomatically { controller.updater.checkForUpdatesInBackground() }
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.checkIfWaiting() }
        }
    }

    func checkForUpdates() {
        checkWhenReady = true
        checkIfWaiting()
    }

    func installReadyUpdate() {
        installReady?()
    }

    private func checkIfWaiting() {
        guard checkWhenReady, controller.updater.canCheckForUpdates else { return }
        checkWhenReady = false
        controller.checkForUpdates(nil)
    }
}

private final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    var onReady: ((String, @escaping () -> Void) -> Void)?

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        onReady?(item.displayVersionString, immediateInstallHandler)
        return true
    }
}
