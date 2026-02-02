import Foundation

public enum MachineSortOrder: String, Codable, CaseIterable, Sendable {
    case name
    case temperature
    case uptime
}
