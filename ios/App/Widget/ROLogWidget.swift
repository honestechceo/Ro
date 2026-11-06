import WidgetKit
import SwiftUI

// RO Log's Home Screen and Lock Screen widget: hours this week against the goal, estimated pay,
// the week's days and how long until the pay period closes. The app writes a small summary into
// the shared App Group each time ROs change; the widget only reads it.

private let appGroup = "group.com.honestechmobileapp.rolog"
private let summaryKey = "rolog.summary"

struct Summary: Codable {
    var hrs: Double = 0
    var goal: Double = 40
    var ros: Int = 0
    var pay: String = ""
    var days: [Double] = []
    var dayLabels: [String] = []
    var weekLabel: String = ""
    var weekEnd: Double = 0          // ms since 1970, end of the pay week (exclusive)
    var periodEnd: Double = 0        // ms since 1970, end of the pay period (exclusive)
    var periodLabel: String = ""
    var updated: Double = 0

    static func load() -> Summary? {
        guard let d = UserDefaults(suiteName: appGroup)?.data(forKey: summaryKey) else { return nil }
        return try? JSONDecoder().decode(Summary.self, from: d)
    }
}

struct Entry: TimelineEntry {
    let date: Date
    let s: Summary?
    var stale: Bool {
        guard let s = s, s.weekEnd > 0 else { return false }
        return date.timeIntervalSince1970 * 1000 >= s.weekEnd
    }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), s: Summary(hrs: 32.4, goal: 45, ros: 18, pay: "$1,037", days: [6.2, 8.1, 5.4, 7.3, 5.4, 0, 0],
                                        dayLabels: ["W", "T", "F", "S", "S", "M", "T"], weekLabel: "Nov 5 – 11"))
    }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : Entry(date: Date(), s: Summary.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let now = Date(), s = Summary.load()
        var entries = [Entry(date: now, s: s)]
        // when the week rolls over without the app being opened, switch to a fresh week on its own
        if let s = s, s.weekEnd > 0 {
            let end = Date(timeIntervalSince1970: s.weekEnd / 1000)
            if end > now { entries.append(Entry(date: end, s: s)) }
        }
        let next = Calendar.current.date(byAdding: .hour, value: 2, to: now) ?? now.addingTimeInterval(7200)
        completion(Timeline(entries: entries, policy: .after(next)))
    }
}

private let accent = Color(red: 0.20, green: 0.55, blue: 0.95)
private let bg = Color(red: 0.043, green: 0.067, blue: 0.094)

private func h1(_ v: Double) -> String { String(format: "%.1f", v) }

private func daysLeft(_ s: Summary, from now: Date) -> Int? {
    guard s.periodEnd > 0 else { return nil }
    let end = Date(timeIntervalSince1970: s.periodEnd / 1000)
    let d = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: now), to: Calendar.current.startOfDay(for: end)).day ?? 0
    return max(0, d)
}

struct Ring: View {
    let pct: Double
    var line: CGFloat = 8
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.14), lineWidth: line)
            Circle().trim(from: 0, to: CGFloat(min(1, max(0.001, pct))))
                .stroke(pct >= 1 ? Color.green : accent, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

struct HomeView: View {
    let e: Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        let s = e.stale ? Summary(goal: e.s?.goal ?? 40, weekLabel: "New week") : (e.s ?? Summary())
        let pct = s.goal > 0 ? s.hrs / s.goal : 0
        Group {
            if e.s == nil {
                VStack(alignment: .leading, spacing: 6) {
                    Text("RO LOG").font(.caption2.weight(.heavy)).foregroundColor(accent)
                    Spacer()
                    Text("Open RO Log to show your hours here.").font(.footnote).foregroundColor(.white)
                }
            } else if family == .systemSmall {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("THIS WEEK").font(.caption2.weight(.heavy)).foregroundColor(.white.opacity(0.6))
                        Spacer()
                        Ring(pct: pct, line: 5).frame(width: 22, height: 22)
                    }
                    Spacer(minLength: 0)
                    Text(h1(s.hrs)).font(.system(size: 40, weight: .bold, design: .rounded)).foregroundColor(.white).minimumScaleFactor(0.6).lineLimit(1)
                    Text("of \(Int(s.goal.rounded())) hr goal").font(.caption).foregroundColor(.white.opacity(0.7))
                    if !s.pay.isEmpty { Text(s.pay).font(.subheadline.weight(.semibold)).foregroundColor(accent) }
                }
            } else {
                HStack(spacing: 14) {
                    ZStack {
                        Ring(pct: pct, line: 9)
                        VStack(spacing: 0) {
                            Text(h1(s.hrs)).font(.system(size: 26, weight: .bold, design: .rounded)).foregroundColor(.white).minimumScaleFactor(0.6)
                            Text("/ \(Int(s.goal.rounded())) hrs").font(.caption2).foregroundColor(.white.opacity(0.7))
                        }
                    }.frame(width: 96, height: 96)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(s.weekLabel.uppercased()).font(.caption2.weight(.heavy)).foregroundColor(.white.opacity(0.6)).lineLimit(1)
                            Spacer()
                            if !s.pay.isEmpty { Text(s.pay).font(.caption.weight(.bold)).foregroundColor(accent) }
                        }
                        Bars(days: s.days, labels: s.dayLabels)
                        HStack {
                            Text("\(s.ros) RO\(s.ros == 1 ? "" : "s")").font(.caption2).foregroundColor(.white.opacity(0.75))
                            Spacer()
                            if let d = daysLeft(s, from: e.date) {
                                Text(d == 0 ? "Pay period ends today" : d == 1 ? "Ends tomorrow" : "\(d) days left")
                                    .font(.caption2.weight(d <= 1 ? .bold : .regular)).foregroundColor(d <= 1 ? .orange : .white.opacity(0.75))
                            }
                        }
                    }
                }
            }
        }
        .padding(family == .systemSmall ? 2 : 0)
        .widgetBackground(bg)
    }
}

struct Bars: View {
    let days: [Double]
    let labels: [String]
    var body: some View {
        let mx = max(1, days.max() ?? 1)
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(days.enumerated()), id: \.offset) { i, v in
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 3).fill(v > 0 ? accent : Color.white.opacity(0.14))
                        .frame(height: max(3, CGFloat(v / mx) * 34))
                    Text(i < labels.count ? labels[i] : "").font(.system(size: 9)).foregroundColor(.white.opacity(0.6))
                }.frame(maxWidth: .infinity)
            }
        }.frame(height: 48, alignment: .bottom)
    }
}

struct LockView: View {
    let e: Entry
    @Environment(\.widgetFamily) var family
    var body: some View {
        let s = e.stale ? Summary(goal: e.s?.goal ?? 40) : (e.s ?? Summary())
        switch family {
        case .accessoryCircular:
            Gauge(value: min(s.hrs, max(s.goal, 0.1)), in: 0...max(s.goal, 0.1)) {
                Text("HRS")
            } currentValueLabel: {
                Text(h1(s.hrs))
            }
            .gaugeStyle(.accessoryCircular)
            .widgetBackground(Color.clear)
        case .accessoryInline:
            Text("\(h1(s.hrs)) hrs this week").widgetBackground(Color.clear)
        default:
            VStack(alignment: .leading, spacing: 1) {
                Text("RO LOG").font(.caption2.weight(.heavy))
                Text("\(h1(s.hrs)) / \(Int(s.goal.rounded())) hrs").font(.headline)
                Text(s.pay.isEmpty ? "\(s.ros) ROs this week" : "\(s.pay) · \(s.ros) ROs").font(.caption)
            }.widgetBackground(Color.clear)
        }
    }
}

extension View {
    @ViewBuilder func widgetBackground(_ color: Color) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            containerBackground(for: .widget) { color }
        } else {
            background(color)
        }
    }
}

struct ROLogHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ROLogHours", provider: Provider()) { e in HomeView(e: e) }
            .configurationDisplayName("Hours this week")
            .description("Flagged hours against your goal, estimated pay and the pay period.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ROLogLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ROLogLock", provider: Provider()) { e in LockView(e: e) }
            .configurationDisplayName("Hours (Lock Screen)")
            .description("Your flagged hours this week.")
            .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct ROLogWidgets: WidgetBundle {
    var body: some Widget {
        ROLogHomeWidget()
        ROLogLockWidget()
    }
}
