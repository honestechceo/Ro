import WidgetKit
import SwiftUI
import AppIntents

// RO Log's widgets. The app writes a small summary into the shared App Group each time ROs change;
// the widgets only read it. Buttons open the app through rolog:// links (new RO, scan, VIN, calculator, pay).
//
//  • Hours this week   small / medium / large (large adds the pay period and the latest ROs)
//  • Pay period        small / medium: hours, est. paycheck, warranty bonus, days left
//  • Quick buttons     small (New RO) / medium (New RO, Scan RO, Scan VIN, Calculator)
//  • Lock Screen       gauge, line and inline text
//  • Control Center / Action button: New RO (iOS 18)

private let appGroup = "group.com.honestechmobileapp.rolog"
private let summaryKey = "rolog.summary"

struct RecentRO: Codable, Hashable {
    var ro: String = ""
    var d: String = ""
    var h: Double = 0
    var t: String = ""
}

struct Summary: Codable {
    var hrs: Double = 0
    var goal: Double = 40
    var ros: Int = 0
    var pay: String = ""
    var today: Double = 0
    var todayRos: Int = 0
    var days: [Double] = []
    var dayLabels: [String] = []
    var weekLabel: String = ""
    var weekEnd: Double = 0          // ms since 1970, end of the pay week (exclusive)
    var periodEnd: Double = 0        // ms since 1970, end of the pay period (exclusive)
    var periodLabel: String = ""
    var periodHrs: Double = 0
    var periodRos: Int = 0
    var periodPay: String = ""
    var periodBonus: Double = 0
    var periodWeekly: Bool = true
    var recent: [RecentRO] = []
    var updated: Double = 0

    init() {}
    init(hrs: Double, goal: Double, ros: Int, pay: String, days: [Double], dayLabels: [String], weekLabel: String) {
        self.hrs = hrs; self.goal = goal; self.ros = ros; self.pay = pay; self.days = days; self.dayLabels = dayLabels; self.weekLabel = weekLabel
    }

    // every field is optional, so an older summary from the app still loads
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hrs = (try? c.decodeIfPresent(Double.self, forKey: .hrs)) ?? 0
        goal = (try? c.decodeIfPresent(Double.self, forKey: .goal)) ?? 40
        ros = (try? c.decodeIfPresent(Int.self, forKey: .ros)) ?? 0
        pay = (try? c.decodeIfPresent(String.self, forKey: .pay)) ?? ""
        today = (try? c.decodeIfPresent(Double.self, forKey: .today)) ?? 0
        todayRos = (try? c.decodeIfPresent(Int.self, forKey: .todayRos)) ?? 0
        days = (try? c.decodeIfPresent([Double].self, forKey: .days)) ?? []
        dayLabels = (try? c.decodeIfPresent([String].self, forKey: .dayLabels)) ?? []
        weekLabel = (try? c.decodeIfPresent(String.self, forKey: .weekLabel)) ?? ""
        weekEnd = (try? c.decodeIfPresent(Double.self, forKey: .weekEnd)) ?? 0
        periodEnd = (try? c.decodeIfPresent(Double.self, forKey: .periodEnd)) ?? 0
        periodLabel = (try? c.decodeIfPresent(String.self, forKey: .periodLabel)) ?? ""
        periodHrs = (try? c.decodeIfPresent(Double.self, forKey: .periodHrs)) ?? 0
        periodRos = (try? c.decodeIfPresent(Int.self, forKey: .periodRos)) ?? 0
        periodPay = (try? c.decodeIfPresent(String.self, forKey: .periodPay)) ?? ""
        periodBonus = (try? c.decodeIfPresent(Double.self, forKey: .periodBonus)) ?? 0
        periodWeekly = (try? c.decodeIfPresent(Bool.self, forKey: .periodWeekly)) ?? true
        recent = (try? c.decodeIfPresent([RecentRO].self, forKey: .recent)) ?? []
        updated = (try? c.decodeIfPresent(Double.self, forKey: .updated)) ?? 0
    }

    static func load() -> Summary? {
        guard let d = UserDefaults(suiteName: appGroup)?.data(forKey: summaryKey) else { return nil }
        return try? JSONDecoder().decode(Summary.self, from: d)
    }

    static var sample: Summary {
        var s = Summary(hrs: 32.4, goal: 45, ros: 18, pay: "$1,037", days: [6.2, 8.1, 5.4, 7.3, 5.4, 0, 0],
                        dayLabels: ["W", "T", "F", "S", "S", "M", "T"], weekLabel: "Nov 5 – 11")
        s.today = 5.4; s.todayRos = 3
        s.periodLabel = "Nov 1 – Nov 15"; s.periodHrs = 52.6; s.periodRos = 29; s.periodPay = "$1,683"; s.periodBonus = 4.2; s.periodWeekly = false
        s.periodEnd = (Date().addingTimeInterval(4 * 86400)).timeIntervalSince1970 * 1000
        s.recent = [RecentRO(ro: "756969", d: "Nov 6", h: 1.8, t: "W"), RecentRO(ro: "756950", d: "Nov 6", h: 2.4, t: "C"),
                    RecentRO(ro: "756941", d: "Nov 5", h: 0.6, t: "C"), RecentRO(ro: "756930", d: "Nov 5", h: 3.1, t: "W")]
        return s
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
    func placeholder(in context: Context) -> Entry { Entry(date: Date(), s: .sample) }
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
private let warrantyColor = Color(red: 0.25, green: 0.75, blue: 0.45)
private let bg = Color(red: 0.043, green: 0.067, blue: 0.094)
private let card = Color.white.opacity(0.07)

private func h1(_ v: Double) -> String { String(format: "%.1f", v) }

private func link(_ path: String) -> URL { URL(string: "rolog://" + path)! }

private func daysLeft(_ s: Summary, from now: Date) -> Int? {
    guard s.periodEnd > 0 else { return nil }
    let end = Date(timeIntervalSince1970: s.periodEnd / 1000)
    let cal = Calendar.current
    let d = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: end)).day ?? 0
    return max(0, d - 1)
}

private func leftText(_ d: Int) -> String { d == 0 ? "Ends today" : d == 1 ? "Ends tomorrow" : "\(d) days left" }

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

struct Bars: View {
    let days: [Double]
    let labels: [String]
    var height: CGFloat = 34
    var body: some View {
        let mx = max(1, days.max() ?? 1)
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(days.enumerated()), id: \.offset) { i, v in
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 3).fill(v > 0 ? accent : Color.white.opacity(0.14))
                        .frame(height: max(3, CGFloat(v / mx) * height))
                    Text(i < labels.count ? labels[i] : "").font(.system(size: 9)).foregroundColor(.white.opacity(0.6))
                }.frame(maxWidth: .infinity)
            }
        }.frame(height: height + 14, alignment: .bottom)
    }
}

struct Caption: View {
    let text: String
    var body: some View { Text(text.uppercased()).font(.caption2.weight(.heavy)).foregroundColor(.white.opacity(0.6)).lineLimit(1) }
}

struct SetupView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RO LOG").font(.caption2.weight(.heavy)).foregroundColor(accent)
            Spacer()
            Text("Open RO Log to show your hours here.").font(.footnote).foregroundColor(.white)
        }
    }
}

// ---------- Hours this week ----------
struct HomeView: View {
    let e: Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        let s = e.stale ? { var x = Summary(); x.goal = e.s?.goal ?? 40; x.weekLabel = "New week"; return x }() : (e.s ?? Summary())
        let pct = s.goal > 0 ? s.hrs / s.goal : 0
        Group {
            if e.s == nil {
                SetupView()
            } else if family == .systemSmall {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Caption(text: "This week")
                        Spacer()
                        Ring(pct: pct, line: 5).frame(width: 22, height: 22)
                    }
                    Spacer(minLength: 0)
                    Text(h1(s.hrs)).font(.system(size: 40, weight: .bold, design: .rounded)).foregroundColor(.white).minimumScaleFactor(0.6).lineLimit(1)
                    Text("of \(Int(s.goal.rounded())) hr goal").font(.caption).foregroundColor(.white.opacity(0.7))
                    if !s.pay.isEmpty { Text(s.pay).font(.subheadline.weight(.semibold)).foregroundColor(accent) }
                }
            } else if family == .systemLarge {
                VStack(alignment: .leading, spacing: 10) {
                    WeekBlock(s: s, pct: pct, date: e.date)
                    PeriodRow(s: s, date: e.date)
                    VStack(alignment: .leading, spacing: 4) {
                        Caption(text: "Latest ROs")
                        if s.recent.isEmpty {
                            Text("No ROs yet this week").font(.caption).foregroundColor(.white.opacity(0.6))
                        }
                        ForEach(s.recent.prefix(4), id: \.self) { r in
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 2).fill(r.t == "W" ? warrantyColor : r.t == "I" ? Color.gray : accent).frame(width: 4, height: 16)
                                Text("RO \(r.ro)").font(.caption.weight(.semibold).monospacedDigit()).foregroundColor(.white).lineLimit(1)
                                Spacer()
                                Text(r.d).font(.caption2).foregroundColor(.white.opacity(0.6))
                                Text("\(h1(r.h)) hrs").font(.caption.weight(.bold).monospacedDigit()).foregroundColor(.white)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 8) {
                        QuickButton(label: "New RO", icon: "plus", path: "new", filled: true)
                        QuickButton(label: "Scan", icon: "doc.text.viewfinder", path: "scan")
                        QuickButton(label: "Calc", icon: "plus.forwardslash.minus", path: "calc")
                    }
                }
            } else {
                WeekBlock(s: s, pct: pct, date: e.date)
            }
        }
        .widgetURL(link(family == .systemLarge ? "home" : "home"))
        .padding(family == .systemSmall ? 2 : 0)
        .widgetBackground(bg)
    }
}

struct WeekBlock: View {
    let s: Summary
    let pct: Double
    let date: Date
    var body: some View {
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
                    Caption(text: s.weekLabel)
                    Spacer()
                    if !s.pay.isEmpty { Text(s.pay).font(.caption.weight(.bold)).foregroundColor(accent) }
                }
                Bars(days: s.days, labels: s.dayLabels)
                HStack {
                    Text("\(s.ros) RO\(s.ros == 1 ? "" : "s")").font(.caption2).foregroundColor(.white.opacity(0.75))
                    Spacer()
                    if s.periodWeekly, let d = daysLeft(s, from: date) {
                        Text(leftText(d)).font(.caption2.weight(d <= 1 ? .bold : .regular)).foregroundColor(d <= 1 ? .orange : .white.opacity(0.75))
                    } else if s.today > 0 {
                        Text("Today \(h1(s.today)) hrs").font(.caption2).foregroundColor(.white.opacity(0.75))
                    }
                }
            }
        }
    }
}

struct PeriodRow: View {
    let s: Summary
    let date: Date
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Caption(text: "Pay period · \(s.periodLabel)")
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(h1(s.periodHrs)).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundColor(.white)
                    Text("hrs · \(s.periodRos) ROs").font(.caption).foregroundColor(.white.opacity(0.7))
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if !s.periodPay.isEmpty { Text(s.periodPay).font(.headline).foregroundColor(accent) }
                if s.periodBonus > 0 { Text("+\(h1(s.periodBonus)) bonus hrs").font(.caption2).foregroundColor(warrantyColor) }
                if let d = daysLeft(s, from: date) {
                    Text(leftText(d)).font(.caption2.weight(d <= 1 ? .bold : .regular)).foregroundColor(d <= 1 ? .orange : .white.opacity(0.7))
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(card))
    }
}

struct QuickButton: View {
    let label: String
    let icon: String
    let path: String
    var filled = false
    var body: some View {
        Link(destination: link(path)) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 18, weight: .semibold))
                Text(label).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundColor(filled ? .white : .white.opacity(0.92))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 14).fill(filled ? accent : card))
        }
    }
}

// ---------- Pay period ----------
struct PeriodView: View {
    let e: Entry
    @Environment(\.widgetFamily) var family
    var body: some View {
        let s = e.s ?? Summary()
        Group {
            if e.s == nil {
                SetupView()
            } else if family == .systemSmall {
                VStack(alignment: .leading, spacing: 3) {
                    Caption(text: "Pay period")
                    Text(s.periodLabel).font(.caption2).foregroundColor(.white.opacity(0.6)).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(h1(s.periodHrs)).font(.system(size: 36, weight: .bold, design: .rounded)).foregroundColor(.white).minimumScaleFactor(0.6).lineLimit(1)
                    Text("hrs · \(s.periodRos) ROs").font(.caption).foregroundColor(.white.opacity(0.7))
                    if !s.periodPay.isEmpty { Text(s.periodPay).font(.subheadline.weight(.semibold)).foregroundColor(accent) }
                    if let d = daysLeft(s, from: e.date) {
                        Text(leftText(d)).font(.caption2.weight(d <= 1 ? .bold : .regular)).foregroundColor(d <= 1 ? .orange : .white.opacity(0.6))
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Caption(text: "Pay period · \(s.periodLabel)")
                        Spacer()
                        if let d = daysLeft(s, from: e.date) {
                            Text(leftText(d)).font(.caption2.weight(.bold)).foregroundColor(d <= 1 ? .orange : .white.opacity(0.7))
                        }
                    }
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(h1(s.periodHrs)).font(.system(size: 40, weight: .bold, design: .rounded)).foregroundColor(.white).minimumScaleFactor(0.6)
                            Text("flagged hrs · \(s.periodRos) ROs").font(.caption).foregroundColor(.white.opacity(0.7))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(s.periodPay.isEmpty ? "Set your rate" : s.periodPay).font(.title3.weight(.bold)).foregroundColor(accent)
                            Text("est. paycheck").font(.caption2).foregroundColor(.white.opacity(0.6))
                            if s.periodBonus > 0 { Text("+\(h1(s.periodBonus)) warranty bonus hrs").font(.caption2).foregroundColor(warrantyColor) }
                        }
                    }
                }
            }
        }
        .widgetURL(link("pay"))
        .padding(family == .systemSmall ? 2 : 0)
        .widgetBackground(bg)
    }
}

// ---------- Quick buttons ----------
struct QuickView: View {
    let e: Entry
    @Environment(\.widgetFamily) var family
    var body: some View {
        let s = e.s ?? Summary()
        Group {
            if family == .systemSmall {
                VStack(alignment: .leading, spacing: 6) {
                    Caption(text: "RO Log")
                    Spacer(minLength: 0)
                    Image(systemName: "plus.circle.fill").font(.system(size: 40)).foregroundColor(accent)
                    Text("New RO").font(.headline).foregroundColor(.white)
                    Text(e.s == nil ? "Tap to start" : "Today \(h1(s.today)) hrs · \(s.todayRos) RO\(s.todayRos == 1 ? "" : "s")").font(.caption2).foregroundColor(.white.opacity(0.65))
                }
                .widgetURL(link("new"))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Caption(text: "RO Log")
                        Spacer()
                        if e.s != nil { Text("Today \(h1(s.today)) hrs · Week \(h1(s.hrs))").font(.caption2.weight(.semibold)).foregroundColor(.white.opacity(0.75)) }
                    }
                    HStack(spacing: 8) {
                        QuickButton(label: "New RO", icon: "plus", path: "new", filled: true)
                        QuickButton(label: "Scan RO", icon: "doc.text.viewfinder", path: "scan")
                        QuickButton(label: "Scan VIN", icon: "barcode.viewfinder", path: "vin")
                        QuickButton(label: "Calculator", icon: "plus.forwardslash.minus", path: "calc")
                    }
                }
            }
        }
        .padding(family == .systemSmall ? 2 : 0)
        .widgetBackground(bg)
    }
}

// ---------- Lock Screen ----------
struct LockView: View {
    let e: Entry
    @Environment(\.widgetFamily) var family
    var body: some View {
        let s = e.stale ? { var x = Summary(); x.goal = e.s?.goal ?? 40; return x }() : (e.s ?? Summary())
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
            .description("Flagged hours against your goal and estimated pay. The large size adds your pay period and latest ROs.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct ROLogPeriodWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ROLogPeriod", provider: Provider()) { e in PeriodView(e: e) }
            .configurationDisplayName("Pay period")
            .description("Hours, estimated paycheck and warranty bonus for the whole pay period, and how many days are left.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ROLogQuickWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ROLogQuick", provider: Provider()) { e in QuickView(e: e) }
            .configurationDisplayName("Quick buttons")
            .description("Start a new RO, scan an RO page or a VIN, or open the calculator in one tap.")
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

// ---------- Control Center and the Action button (iOS 18) ----------
@available(iOSApplicationExtension 18.0, *)
struct ROLogNewROControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.honestechmobileapp.rolog.newro") {
            ControlWidgetButton(action: OpenURLIntent(URL(string: "rolog://new")!)) {
                Label("New RO", systemImage: "plus.circle")
            }
        }
        .displayName("New RO")
        .description("Open RO Log on a new repair order.")
    }
}

@available(iOSApplicationExtension 18.0, *)
struct ROLogScanVINControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.honestechmobileapp.rolog.scanvin") {
            ControlWidgetButton(action: OpenURLIntent(URL(string: "rolog://vin")!)) {
                Label("Scan VIN", systemImage: "barcode.viewfinder")
            }
        }
        .displayName("Scan VIN")
        .description("Open RO Log on a new RO with the VIN scanner.")
    }
}

// ---------- Job timer on the Lock Screen and in the Dynamic Island ----------
struct ROTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ROTimerAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: "timer").font(.title2).foregroundColor(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("RO \(context.attributes.ro)").font(.headline).foregroundColor(.white)
                    Text(context.state.flagged > 0 ? "Flagged \(h1(context.state.flagged)) hrs" : "Job timer").font(.caption).foregroundColor(.white.opacity(0.7))
                }
                Spacer()
                Text(context.state.startedAt, style: .timer).font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundColor(.white).multilineTextAlignment(.trailing).frame(maxWidth: 130, alignment: .trailing)
            }
            .padding(16)
            .activityBackgroundTint(bg)
            .activitySystemActionForegroundColor(.white)
            .widgetURL(link("timer"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("RO \(context.attributes.ro)", systemImage: "timer").font(.headline).foregroundColor(accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.startedAt, style: .timer).font(.title2.weight(.bold)).monospacedDigit().multilineTextAlignment(.trailing).frame(maxWidth: 110)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.flagged > 0 ? "Flagged \(h1(context.state.flagged)) hrs · tap to open the RO" : "Tap to open the RO").font(.caption).foregroundColor(.secondary)
                }
            } compactLeading: {
                Image(systemName: "timer").foregroundColor(accent)
            } compactTrailing: {
                Text(context.state.startedAt, style: .timer).monospacedDigit().frame(maxWidth: 56).font(.caption.weight(.semibold))
            } minimal: {
                Image(systemName: "timer").foregroundColor(accent)
            }
            .widgetURL(link("timer"))
        }
    }
}

@main
struct ROLogWidgets: WidgetBundle {
    var body: some Widget {
        ROLogHomeWidget()
        ROLogPeriodWidget()
        ROLogQuickWidget()
        ROLogLockWidget()
        ROTimerLiveActivity()
        if #available(iOSApplicationExtension 18.0, *) {
            ROLogNewROControl()
            ROLogScanVINControl()
        }
    }
}
