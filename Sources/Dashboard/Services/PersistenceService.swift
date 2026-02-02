import Foundation
import Shared

/// Persists machine identities and sort order to a JSON file in Application Support.
final class PersistenceService {
    private let fileURL: URL

    struct StoredData: Codable {
        var sortOrder: MachineSortOrder
        var machines: [MachineIdentity]
    }

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("ComputerDashboard", isDirectory: true)

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)

        fileURL = appDir.appendingPathComponent("machines.json")
    }

    func load() -> StoredData {
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder.withISO8601.decode(StoredData.self, from: data) else {
            return StoredData(sortOrder: .name, machines: [])
        }
        return stored
    }

    func save(_ data: StoredData) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let jsonData = try? encoder.encode(data) else { return }
        try? jsonData.write(to: fileURL, options: .atomic)
    }

    func saveMachines(_ machines: [MachineIdentity], sortOrder: MachineSortOrder) {
        save(StoredData(sortOrder: sortOrder, machines: machines))
    }
}

private extension JSONDecoder {
    static let withISO8601: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
