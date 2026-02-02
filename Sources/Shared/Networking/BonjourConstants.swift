import Foundation

public enum BonjourConstants {
    public static let serviceType = "_computerdash._tcp"
    public static let serviceDomain = "local."
    public static let statusPath = "/status"
    public static let defaultPort: UInt16 = 49990
    public static let portRetryCount: UInt16 = 10
}
