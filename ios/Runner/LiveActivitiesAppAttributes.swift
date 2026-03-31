import ActivityKit
import Foundation

/// Required by live_activities plugin — must be named exactly LiveActivitiesAppAttributes.
/// This file must exist in BOTH the Runner target AND the Widget Extension target.
struct LiveActivitiesAppAttributes: ActivityAttributes, Identifiable {
    public typealias LiveDeliveryData = ContentState
    public struct ContentState: Codable, Hashable { }
    var id = UUID()
}

extension LiveActivitiesAppAttributes {
    func prefixedKey(_ key: String) -> String {
        return "\(id)_\(key)"
    }
}
