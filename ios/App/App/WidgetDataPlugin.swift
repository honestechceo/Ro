import Foundation
import Capacitor
import WidgetKit

// Hands the Home Screen widget a small summary (hours, goal, pay, days) through the shared App Group,
// then asks iOS to redraw the widget.
// update({ json }) -> { shared }   shared is false until the App Group is set up for the app.
@objc(WidgetDataPlugin)
public class WidgetDataPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "WidgetDataPlugin"
    public let jsName = "WidgetData"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "update", returnType: CAPPluginReturnPromise)
    ]

    static let appGroup = "group.com.honestechmobileapp.rolog"

    @objc func update(_ call: CAPPluginCall) {
        guard let json = call.getString("json"), let data = json.data(using: .utf8) else {
            call.reject("Nothing to show"); return
        }
        let shared = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetDataPlugin.appGroup) != nil
        if shared, let d = UserDefaults(suiteName: WidgetDataPlugin.appGroup) {
            d.set(data, forKey: "rolog.summary")
        }
        WidgetCenter.shared.reloadAllTimelines()
        call.resolve(["shared": shared])
    }
}
