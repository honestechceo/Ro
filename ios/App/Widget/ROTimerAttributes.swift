import Foundation
#if canImport(ActivityKit)
import ActivityKit

// Shared by the app (starts and ends the timer) and the widget extension (draws it on the
// Lock Screen and in the Dynamic Island). The clock counts on its own from startedAt.
@available(iOS 16.1, *)
public struct ROTimerAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var startedAt: Date      // now minus time already worked, so the clock shows the total
        public var flagged: Double      // flagged hours on the RO, for "beat the book"
        public init(startedAt: Date, flagged: Double) { self.startedAt = startedAt; self.flagged = flagged }
    }
    public var ro: String
    public init(ro: String) { self.ro = ro }
}
#endif
