import Foundation

/// A widget slot that can hold an app icon on a machine tile.
public struct WidgetSlot: Codable, Sendable, Equatable, Identifiable {
    /// Slot index (0, 1, or 2)
    public var id: Int

    /// The assigned app, or nil if empty
    public var appIdentifier: AppIdentifier?

    public init(id: Int, appIdentifier: AppIdentifier? = nil) {
        self.id = id
        self.appIdentifier = appIdentifier
    }

    /// Whether this slot has no app assigned
    public var isEmpty: Bool { appIdentifier == nil }

    /// Creates the default set of 3 empty slots
    public static var defaults: [WidgetSlot] {
        [WidgetSlot(id: 0), WidgetSlot(id: 1), WidgetSlot(id: 2)]
    }
}
