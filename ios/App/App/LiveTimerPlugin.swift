import Foundation
import Capacitor
#if canImport(ActivityKit)
import ActivityKit
#endif

// The job timer on the Lock Screen and in the Dynamic Island.
// start({ ro, startedAt (ms), flagged }) ends any running timer first; end() stops it.
@objc(LiveTimerPlugin)
public class LiveTimerPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "LiveTimerPlugin"
    public let jsName = "LiveTimer"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "start", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "end", returnType: CAPPluginReturnPromise)
    ]

    @objc func start(_ call: CAPPluginCall) {
        let ro = call.getString("ro") ?? "RO"
        let started = Date(timeIntervalSince1970: (call.getDouble("startedAt") ?? Date().timeIntervalSince1970 * 1000) / 1000)
        let flagged = call.getDouble("flagged") ?? 0
        #if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { call.resolve(["started": false, "reason": "off"]); return }
            Task {
                for a in Activity<ROTimerAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
                do {
                    _ = try Activity.request(attributes: ROTimerAttributes(ro: ro),
                                             content: ActivityContent(state: .init(startedAt: started, flagged: flagged), staleDate: nil),
                                             pushType: nil)
                    call.resolve(["started": true])
                } catch {
                    call.resolve(["started": false, "reason": error.localizedDescription])
                }
            }
            return
        }
        #endif
        call.resolve(["started": false, "reason": "unsupported"])
    }

    @objc func end(_ call: CAPPluginCall) {
        #if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            Task {
                for a in Activity<ROTimerAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
                call.resolve()
            }
            return
        }
        #endif
        call.resolve()
    }
}
