import Foundation
import Capacitor

// RO Log's folder in the person's own iCloud Drive (Files app → iCloud Drive → RO Log).
// Backups and RO files saved here follow them to a new iPhone or an iPad. It uses their
// iCloud storage, never ours, so there's no account or server to pay for.
//
// status()                      -> { available, signedIn }
// write({ path, data })         data is base64; folders are made as needed
// list({ path })                -> { files: [{ name, size, modified, dir, downloaded }] }
// read({ path })                -> { data }  (downloads the file from iCloud first if needed)
// remove({ path })
@objc(ICloudDrivePlugin)
public class ICloudDrivePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "ICloudDrivePlugin"
    public let jsName = "ICloudDrive"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "status", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "write", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "list", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "read", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "remove", returnType: CAPPluginReturnPromise)
    ]

    static let containerId = "iCloud.com.honestechmobileapp.rolog"
    private let queue = DispatchQueue(label: "rolog.icloud", qos: .userInitiated)

    // the container lookup can be slow the first time, so it's always called off the main thread
    private func docsURL() -> URL? {
        guard FileManager.default.ubiquityIdentityToken != nil,
              let root = FileManager.default.url(forUbiquityContainerIdentifier: ICloudDrivePlugin.containerId) else { return nil }
        let docs = root.appendingPathComponent("Documents", isDirectory: true)
        if !FileManager.default.fileExists(atPath: docs.path) {
            try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        }
        return docs
    }

    private func target(_ call: CAPPluginCall) -> URL? {
        let raw = (call.getString("path") ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parts = raw.split(separator: "/").map(String.init)
        if parts.contains("..") || parts.contains(".") { return nil }
        guard let docs = docsURL() else { return nil }
        return parts.reduce(docs) { $0.appendingPathComponent($1) }
    }

    private func fail(_ call: CAPPluginCall, _ msg: String) {
        DispatchQueue.main.async { call.reject(msg) }
    }

    @objc func status(_ call: CAPPluginCall) {
        queue.async {
            let signedIn = FileManager.default.ubiquityIdentityToken != nil
            let ok = signedIn && self.docsURL() != nil
            DispatchQueue.main.async { call.resolve(["available": ok, "signedIn": signedIn]) }
        }
    }

    @objc func write(_ call: CAPPluginCall) {
        guard let b64 = call.getString("data"), let data = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) else {
            call.reject("Nothing to save"); return
        }
        queue.async {
            guard let url = self.target(call) else { self.fail(call, "iCloud Drive isn't available"); return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            var coordErr: NSError?
            var writeErr: Error?
            NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forReplacing, error: &coordErr) { u in
                do { try data.write(to: u, options: .atomic) } catch { writeErr = error }
            }
            if let e = writeErr ?? coordErr { self.fail(call, "Couldn't save to iCloud Drive: \(e.localizedDescription)"); return }
            DispatchQueue.main.async { call.resolve(["path": url.path]) }
        }
    }

    @objc func list(_ call: CAPPluginCall) {
        queue.async {
            guard let dir = self.target(call) else { self.fail(call, "iCloud Drive isn't available"); return }
            let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey]
            let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: [])) ?? []
            var out: [[String: Any]] = []
            for u in items {
                var name = u.lastPathComponent
                var downloaded = true
                // files that live only in iCloud show up as ".Name.icloud" until they're downloaded
                if name.hasPrefix("."), name.hasSuffix(".icloud") {
                    name = String(name.dropFirst().dropLast(7))
                    downloaded = false
                    try? FileManager.default.startDownloadingUbiquitousItem(at: dir.appendingPathComponent(name))
                } else if name.hasPrefix(".") { continue }
                let v = try? u.resourceValues(forKeys: Set(keys))
                out.append([
                    "name": name,
                    "size": v?.fileSize ?? 0,
                    "modified": (v?.contentModificationDate ?? Date.distantPast).timeIntervalSince1970 * 1000,
                    "dir": v?.isDirectory ?? false,
                    "downloaded": downloaded
                ])
            }
            DispatchQueue.main.async { call.resolve(["files": out]) }
        }
    }

    @objc func read(_ call: CAPPluginCall) {
        queue.async {
            guard let url = self.target(call) else { self.fail(call, "iCloud Drive isn't available"); return }
            let fm = FileManager.default
            if !fm.fileExists(atPath: url.path) {
                try? fm.startDownloadingUbiquitousItem(at: url)
                var waited = 0.0
                while !fm.fileExists(atPath: url.path) && waited < 25 { Thread.sleep(forTimeInterval: 0.5); waited += 0.5 }
            }
            var coordErr: NSError?
            var data: Data?
            NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordErr) { u in
                data = try? Data(contentsOf: u)
            }
            guard let d = data else { self.fail(call, "That file is still downloading from iCloud. Try again in a moment."); return }
            DispatchQueue.main.async { call.resolve(["data": d.base64EncodedString()]) }
        }
    }

    @objc func remove(_ call: CAPPluginCall) {
        queue.async {
            guard let url = self.target(call) else { self.fail(call, "iCloud Drive isn't available"); return }
            var coordErr: NSError?
            NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forDeleting, error: &coordErr) { u in
                try? FileManager.default.removeItem(at: u)
            }
            DispatchQueue.main.async { call.resolve() }
        }
    }
}
