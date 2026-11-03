import Foundation
import UIKit
import Vision
import Capacitor

// Reads printed and handwritten text from a photo on the iPhone itself (Apple Vision).
// No internet, no Google key, no cost per scan.
//
// read({ data: <base64 JPEG>, fast?: Bool })
//   -> { words: [{ t, x, y, w, h, c, s: [{ t, x, y, w, h }] }], text, w, h }
// Boxes are in pixels of the image that was sent, top-left origin: the same shape the
// app's Google relay returns, so the app's RO and repair-sheet parsers work unchanged.
@objc(TextReaderPlugin)
public class TextReaderPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "TextReaderPlugin"
    public let jsName = "TextReader"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "isAvailable", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "read", returnType: CAPPluginReturnPromise)
    ]

    @objc func isAvailable(_ call: CAPPluginCall) {
        call.resolve(["available": true])
    }

    @objc func read(_ call: CAPPluginCall) {
        guard let b64 = call.getString("data"),
              let data = Data(base64Encoded: b64.components(separatedBy: ",").last ?? b64, options: .ignoreUnknownCharacters),
              let img = UIImage(data: data), let cg = img.cgImage else {
            call.reject("Couldn't read that photo"); return
        }
        let fast = call.getBool("fast") ?? false
        let W = CGFloat(cg.width), H = CGFloat(cg.height)
        DispatchQueue.global(qos: .userInitiated).async {
            let req = VNRecognizeTextRequest()
            req.recognitionLevel = fast ? .fast : .accurate
            req.usesLanguageCorrection = false
            req.recognitionLanguages = ["en-US"]
            req.minimumTextHeight = 0.006
            if #available(iOS 16.0, *) { req.automaticallyDetectsLanguage = false }
            let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
            do { try handler.perform([req]) } catch {
                DispatchQueue.main.async { call.reject("The text reader failed: \(error.localizedDescription)") }
                return
            }
            // Vision boxes are 0-1 with the origin at the bottom left; the app wants pixels from the top left.
            func px(_ r: CGRect) -> [String: Any] {
                let x = r.minX * W, y = (1 - r.maxY) * H
                return ["x": Double(x.rounded()), "y": Double(y.rounded()), "w": Double((r.width * W).rounded()), "h": Double((r.height * H).rounded())]
            }
            var words: [[String: Any]] = []
            var lines: [String] = []
            for obs in req.results ?? [] {
                guard let cand = obs.topCandidates(1).first else { continue }
                let str = cand.string
                lines.append(str)
                var i = str.startIndex
                while i < str.endIndex {
                    // one word = a run of non-space characters
                    while i < str.endIndex, str[i].isWhitespace { i = str.index(after: i) }
                    if i >= str.endIndex { break }
                    var j = i
                    while j < str.endIndex, !str[j].isWhitespace { j = str.index(after: j) }
                    let range = i..<j
                    let wordBox = (try? cand.boundingBox(for: range))?.boundingBox ?? obs.boundingBox
                    var w = px(wordBox)
                    w["t"] = String(str[range])
                    w["c"] = Double(cand.confidence)
                    var syms: [[String: Any]] = []
                    var k = i
                    while k < j {
                        let n = str.index(after: k)
                        if let b = (try? cand.boundingBox(for: k..<n))?.boundingBox {
                            var s = px(b); s["t"] = String(str[k..<n]); syms.append(s)
                        }
                        k = n
                    }
                    w["s"] = syms
                    words.append(w)
                    i = j
                }
            }
            let out: [String: Any] = ["words": words, "text": lines.joined(separator: "\n"), "w": Double(W), "h": Double(H)]
            DispatchQueue.main.async { call.resolve(out) }
        }
    }
}
