import ArchSightKit
import Observation

/// App-level owner of the single shared core session. Every window reads the
/// same endpoint so only one core process runs regardless of window count.
/// @MainActor is declared because AppCore is only ever accessed from SwiftUI
/// views and `.task` closures, which all run on the main actor.
@MainActor
@Observable
final class AppCore {
    private(set) var status: CoreSessionStatus = .disconnected
    private(set) var endpoint: CoreServiceEndpoint?

    @ObservationIgnored private let session: CoreSession?

    init(session: CoreSession? = CoreSessionFactory.fromEnvironment()) {
        self.session = session
    }

    /// Connects once; safe to call from every window's `.task`.
    func connectIfNeeded() {
        guard let session, endpoint == nil else {
            return
        }
        status = .connecting
        do {
            _ = try session.connect()
            status = session.status
            endpoint = session.serviceEndpoint
        } catch {
            status = session.status
        }
    }
}
