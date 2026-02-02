import Foundation
import Network
import Shared

/// Discovers agents on the local network via Bonjour using NWBrowser.
final class DiscoveryService {
    /// Called when a new endpoint is discovered.
    var onEndpointFound: ((NWEndpoint, String) -> Void)?
    /// Called when an endpoint is lost.
    var onEndpointLost: ((String) -> Void)?

    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "com.computerdash.discovery")
    /// Track discovered endpoints by service name
    private var discovered: [String: NWEndpoint] = [:]

    func startBrowsing() {
        let params = NWParameters()
        params.includePeerToPeer = true

        browser = NWBrowser(
            for: .bonjour(type: BonjourConstants.serviceType, domain: BonjourConstants.serviceDomain),
            using: params
        )

        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            self?.handleChanges(results: results, changes: changes)
        }

        browser?.stateUpdateHandler = { state in
            switch state {
            case .failed:
                // Restart after delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                    self?.browser?.cancel()
                    self?.startBrowsing()
                }
            default:
                break
            }
        }

        browser?.start(queue: queue)
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
    }

    func endpoint(forServiceName name: String) -> NWEndpoint? {
        discovered[name]
    }

    private func handleChanges(results: Set<NWBrowser.Result>, changes: Set<NWBrowser.Result.Change>) {
        for change in changes {
            switch change {
            case .added(let result):
                if case .service(let name, _, _, _) = result.endpoint {
                    discovered[name] = result.endpoint
                    onEndpointFound?(result.endpoint, name)
                }
            case .removed(let result):
                if case .service(let name, _, _, _) = result.endpoint {
                    discovered.removeValue(forKey: name)
                    onEndpointLost?(name)
                }
            default:
                break
            }
        }
    }
}
