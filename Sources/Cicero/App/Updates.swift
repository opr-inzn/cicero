import Foundation
import Observation
import Sparkle

@Observable
final class Updates {
    let isAvailable = Bundle.main.bundleURL.pathExtension == "app"
    var checksAutomatically: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = checksAutomatically }
    }

    @ObservationIgnored private let controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    @ObservationIgnored private var observation: NSKeyValueObservation?
    @ObservationIgnored private var checkWhenReady = false

    init() {
        checksAutomatically = controller.updater.automaticallyChecksForUpdates
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

    private func checkIfWaiting() {
        guard checkWhenReady, controller.updater.canCheckForUpdates else { return }
        checkWhenReady = false
        controller.checkForUpdates(nil)
    }
}
