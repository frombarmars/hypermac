// Minimal Hyperliquid-themed menu bar panel.

import AppKit
import Charts
import ServiceManagement
import SwiftUI

// MARK: - Theme

enum HL {
    static let bg = Color(hex: 0x0F1A1F)
    static let line = Color.white.opacity(0.06)
    static let mint = Color(hex: 0x97FCE4)
    static let up = Color(hex: 0x1FD69F)
    static let down = Color(hex: 0xED7088)
    static let warn = Color(hex: 0xF5B651)
    static let text = Color(hex: 0xF6FEFD)
    static let muted = Color(hex: 0x8E9C9B)
    static let faint = Color(hex: 0x56676A)

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// A ScrollView that sizes itself to its content (up to maxHeight). A bare ScrollView
/// inside a MenuBarExtra window collapses to zero height.
struct FitScroll<Content: View>: View {
    var maxHeight: CGFloat = 540
    @ViewBuilder var content: Content
    @State private var height: CGFloat = 300

    var body: some View {
        ScrollView {
            content.background(GeometryReader { g in
                Color.clear.preference(key: HeightKey.self, value: g.size.height)
            })
        }
        .scrollIndicators(.never)
        .frame(height: min(height, maxHeight))
        .onPreferenceChange(HeightKey.self) { height = $0 }
    }
}

private struct HeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct QuietButton: ButtonStyle {
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(hover ? HL.mint : HL.faint)
            .opacity(configuration.isPressed ? 0.5 : 1)
            .contentShape(Rectangle())
            .onHover { hover = $0 }
    }
}

// MARK: - Panel

struct PanelView: View {
    static let logo = Bundle.main.image(forResource: "LogoMark") ?? NSImage()
    @EnvironmentObject var store: Store
    @AppStorage("hideAmounts") private var hide = false
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if showSettings || store.active == nil {
                FitScroll { SettingsView(close: { showSettings = false }) }
            } else if let s = store.snapshot {
                FitScroll {
                    VStack(alignment: .leading, spacing: 22) {
                        Hero(s: s, hide: hide)
                        Stats(s: s, hide: hide)
                        PositionsList(s: s, hide: hide)
                        SpotList(s: s, hide: hide)
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 16)
                }
            } else {
                Group {
                    if let e = store.error {
                        VStack(spacing: 8) {
                            Text(e).foregroundStyle(HL.muted).multilineTextAlignment(.center)
                            Button("Retry") { Task { await store.refresh() } }.buttonStyle(QuietButton())
                        }
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                .font(HL.font(12))
                .frame(maxWidth: .infinity, minHeight: 160)
            }
            footer
        }
        .frame(width: 340)
        .background(HL.bg)
        .environment(\.colorScheme, .dark)
        .tint(HL.mint)
        .task { await store.refresh() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: Self.logo).resizable().interpolation(.high).frame(width: 18, height: 18)
            if store.config.wallets.count > 1 {
                Menu {
                    ForEach(store.config.wallets) { w in
                        Button(w.label + (w.address == store.active?.address ? "  ✓" : "")) { store.select(w) }
                    }
                } label: {
                    Text(store.active?.label ?? "")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            } else {
                Text(store.active?.label ?? "HyperMac").foregroundStyle(HL.text)
            }
            Spacer()
            Button {
                Task { await store.refresh() }
            } label: {
                Circle()
                    .fill(store.error != nil ? HL.warn : HL.mint)
                    .frame(width: 6, height: 6)
                    .opacity(store.loading ? 0.3 : 1)
                    .animation(.easeInOut(duration: 0.4), value: store.loading)
                    .padding(6)
            }
            .buttonStyle(.plain)
            .help(store.error ?? "Live · click to refresh")
        }
        .font(HL.font(13, .medium))
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Button { store.openExplorer() } label: { Image(systemName: "arrow.up.right") }
                .help("Open in Hyperliquid explorer")
            Button { hide.toggle() } label: { Image(systemName: hide ? "eye.slash" : "eye") }
                .help(hide ? "Show balances" : "Hide balances")
            Spacer()
            Button { showSettings.toggle() } label: { Image(systemName: showSettings ? "xmark" : "gearshape") }
                .help("Settings")
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                .help("Quit")
        }
        .buttonStyle(QuietButton())
        .font(.system(size: 12))
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Rectangle().fill(HL.line).frame(height: 1) }
    }
}

// MARK: - Hero: total, change, chart

struct Hero: View {
    let s: Snapshot
    let hide: Bool
    @AppStorage("chartRange") private var range = "day"
    @State private var hover: (t: Double, v: Double)?

    private let ranges = [("day", "24H"), ("week", "7D"), ("month", "30D"), ("allTime", "ALL")]

    private var points: [(t: Double, v: Double)] {
        guard let se = s.history[range] else { return [] }
        var pts = zip(se.t, se.value).map { (t: $0, v: $1) }
        if let last = pts.last, s.updated > last.t { pts.append((s.updated, s.total)) }
        return pts
    }

    private var change: Double {
        if range == "day" { return s.pnlDay }
        guard let p = s.history[range]?.pnl, let a = p.first, let b = p.last else { return 0 }
        return b - a
    }

    private var changePct: Double {
        if range == "day" { return s.pnlDayPct }
        let base = s.total - change
        return base > 0 ? change / base : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(hide ? "$••••" : Fmt.usd(hover?.v ?? s.total))
                .font(HL.font(32, .medium))
                .foregroundStyle(HL.text)
                .lineLimit(1).minimumScaleFactor(0.6)
            Group {
                if let h = hover {
                    Text(Date(timeIntervalSince1970: h.t).formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(HL.muted)
                } else {
                    Text("\(hide ? "" : Fmt.usd(change, signed: true) + "  ")\(Fmt.pct(changePct))")
                        .foregroundStyle(pnlColor(change))
                }
            }
            .font(HL.font(12))
            chart.frame(height: 56).padding(.top, 12)
            HStack(spacing: 14) {
                ForEach(ranges, id: \.0) { key, title in
                    Button(title) { range = key }
                        .buttonStyle(.plain)
                        .foregroundStyle(range == key ? HL.mint : HL.faint)
                }
                Spacer()
            }
            .font(HL.font(10, .semibold))
            .padding(.top, 6)
        }
    }

    @ViewBuilder private var chart: some View {
        let pts = points
        if pts.count >= 2 {
            let lo = pts.map(\.v).min()!, hi = pts.map(\.v).max()!
            let pad = max((hi - lo) * 0.1, 0.01)
            let color = pts.last!.v >= pts.first!.v ? HL.mint : HL.down
            Chart {
                ForEach(Array(pts.enumerated()), id: \.offset) { _, p in
                    LineMark(x: .value("t", p.t), y: .value("v", p.v))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
                }
                if let h = hover {
                    PointMark(x: .value("t", h.t), y: .value("v", h.v)).foregroundStyle(color).symbolSize(25)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: (lo - pad)...(hi + pad))
            .chartXScale(domain: pts.first!.t...pts.last!.t)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let loc):
                                guard let frame = proxy.plotFrame,
                                      let t: Double = proxy.value(atX: loc.x - geo[frame].origin.x) else { return }
                                hover = pts.min { abs($0.t - t) < abs($1.t - t) }
                            case .ended:
                                hover = nil
                            }
                        }
                }
            }
        } else {
            Color.clear
        }
    }
}

// MARK: - Key numbers

struct Stats: View {
    let s: Snapshot
    let hide: Bool

    var body: some View {
        let margin = s.perpEquity > 0 ? s.marginUsed / s.perpEquity : 0
        VStack(spacing: 7) {
            row("Unrealized PnL", Fmt.usd(s.upnl, signed: true, hide: hide), pnlColor(s.upnl))
            row("Perps", Fmt.usd(s.perpEquity, hide: hide))
            row("Spot", Fmt.usd(s.spotValue, hide: hide))
            row("Withdrawable", Fmt.usd(s.withdrawable, hide: hide))
            if s.notional > 0 {
                row("Leverage", String(format: "%.2fx", s.leverage),
                    s.leverage > 10 ? HL.down : s.leverage > 5 ? HL.warn : HL.text)
                row("Margin used", Fmt.pct(margin, signed: false),
                    margin > 0.8 ? HL.down : margin > 0.6 ? HL.warn : HL.text)
            }
            if s.stakedHype > 0 { row("Staked", "\(Fmt.amount(s.stakedHype)) HYPE") }
            if s.vaultValue >= 0.01 { row("Vaults", Fmt.usd(s.vaultValue, hide: hide)) }
            if s.evmHype >= 0.0001 { row("HyperEVM", "\(Fmt.amount(s.evmHype)) HYPE") }
        }
    }

    private func row(_ k: String, _ v: String, _ color: Color = HL.text) -> some View {
        HStack {
            Text(k).foregroundStyle(HL.muted)
            Spacer()
            Text(v).foregroundStyle(color)
        }
        .font(HL.font(12))
    }
}

// MARK: - Positions & spot

struct SectionTitle: View {
    let title: String
    let detail: String
    var body: some View {
        HStack {
            Text(title).foregroundStyle(HL.muted)
            Spacer()
            Text(detail).foregroundStyle(HL.faint)
        }
        .font(HL.font(11, .medium))
        .padding(.bottom, 2)
    }
}

struct PositionsList: View {
    let s: Snapshot
    let hide: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle(title: "Positions",
                         detail: s.orders.isEmpty ? "\(s.positions.count)"
                             : "\(s.positions.count) · \(s.orders.count) order\(s.orders.count == 1 ? "" : "s")")
            if s.positions.isEmpty {
                Text("None").font(HL.font(12)).foregroundStyle(HL.faint).padding(.vertical, 8)
            }
            ForEach(Array(s.positions.enumerated()), id: \.element.id) { i, p in
                if i > 0 { Rectangle().fill(HL.line).frame(height: 1) }
                row(p)
            }
        }
    }

    private func row(_ p: Position) -> some View {
        let name = p.coin.split(separator: ":").last.map(String.init) ?? p.coin
        let long = p.side == "long"
        let d = p.liqDistance
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(name).foregroundStyle(HL.text)
                Text("\(long ? "Long" : "Short") \(p.leverage.map { "\($0)x" } ?? "")")
                    .foregroundStyle(long ? HL.up : HL.down)
                Spacer()
                Text(Fmt.usd(p.upnl, signed: true, hide: hide)).foregroundStyle(pnlColor(p.upnl))
                Text(Fmt.pct(p.roe)).foregroundStyle(pnlColor(p.upnl).opacity(0.7))
            }
            .font(HL.font(13, .medium))
            HStack(spacing: 0) {
                Text("\(Fmt.compact(p.value, hide: hide)) · \(Fmt.price(p.entry)) → \(Fmt.price(p.mark))")
                    .foregroundStyle(HL.faint)
                Spacer()
                if let liq = p.liq, let d {
                    Text("liq \(Fmt.price(liq)) · \(Fmt.pct(d, signed: false))")
                        .foregroundStyle(d < 0.1 ? HL.down : d < 0.25 ? HL.warn : HL.faint)
                }
            }
            .font(HL.font(11))
        }
        .padding(.vertical, 9)
    }
}

struct SpotList: View {
    let s: Snapshot
    let hide: Bool

    var body: some View {
        let rows = s.spot.filter { $0.value >= 1 }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                SectionTitle(title: "Spot", detail: "\(rows.count)")
                ForEach(rows.prefix(10)) { r in
                    HStack {
                        Text(r.coin).foregroundStyle(HL.text)
                        Text(hide ? "" : Fmt.amount(r.amount)).foregroundStyle(HL.faint)
                        Spacer()
                        if let p = r.pnlPct { Text(Fmt.pct(p)).foregroundStyle(pnlColor(p).opacity(0.7)) }
                        Text(Fmt.usd(r.value, hide: hide)).foregroundStyle(HL.text)
                    }
                    .font(HL.font(12))
                }
            }
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @AppStorage("labelMode") private var labelMode = "total"
    @State private var address = ""
    @State private var label = ""
    @State private var addError: String?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if store.config.wallets.isEmpty {
                Text("Paste your public Hyperliquid address. Read-only — never a private key.")
                    .font(HL.font(12)).foregroundStyle(HL.muted)
            }
            VStack(alignment: .leading, spacing: 8) {
                field("0x… address", $address, mono: true)
                HStack(spacing: 8) {
                    field("Label", $label)
                    Button("Add") {
                        addError = store.addWallet(address: address, label: label)
                        if addError == nil {
                            address = ""
                            label = ""
                            close()
                        }
                    }
                    .buttonStyle(.plain)
                    .font(HL.font(12, .semibold))
                    .foregroundStyle(address.isEmpty ? HL.faint : HL.mint)
                    .keyboardShortcut(.defaultAction)
                    .disabled(address.isEmpty)
                }
                if let e = addError { Text(e).font(HL.font(11)).foregroundStyle(HL.down) }
            }
            if !store.config.wallets.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(store.config.wallets) { w in
                        HStack {
                            Text(w.label).foregroundStyle(w.address == store.active?.address ? HL.mint : HL.text)
                            Text(Fmt.short(w.address)).foregroundStyle(HL.faint)
                            Spacer()
                            Button { store.remove(w) } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(QuietButton())
                                .help("Forget")
                        }
                        .font(HL.font(12))
                        .contentShape(Rectangle())
                        .onTapGesture { store.select(w); close() }
                    }
                }
                VStack(spacing: 10) {
                    option("Menu bar") {
                        Picker("", selection: $labelMode) {
                            Text("Total").tag("total")
                            Text("24h PnL").tag("pnl24")
                            Text("Unrealized PnL").tag("upnl")
                            Text("Icon only").tag("icon")
                        }
                    }
                    option("Refresh") {
                        Picker("", selection: Binding(get: { store.config.refresh }, set: { store.setRefresh($0) })) {
                            Text("10s").tag(10)
                            Text("15s").tag(15)
                            Text("30s").tag(30)
                            Text("1m").tag(60)
                            Text("5m").tag(300)
                        }
                    }
                    option("Launch at login") {
                        Toggle("", isOn: $launchAtLogin)
                            .toggleStyle(.switch).controlSize(.mini)
                            .onChange(of: launchAtLogin) { _, on in
                                do {
                                    if on { try SMAppService.mainApp.register() }
                                    else { try SMAppService.mainApp.unregister() }
                                } catch {
                                    launchAtLogin = SMAppService.mainApp.status == .enabled
                                }
                            }
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 4) {
                Text("HyperMac \(Hyperliquid.appVersion) · read-only · open source")
                Spacer()
                Link("GitHub", destination: URL(string: "https://github.com/frombarmars/hypermac")!)
                    .foregroundStyle(HL.mint)
            }
            .font(HL.font(10))
            .foregroundStyle(HL.faint)
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
        }
    }

    private func field(_ placeholder: String, _ text: Binding<String>, mono: Bool = false) -> some View {
        TextField("", text: text, prompt: Text(placeholder).foregroundColor(HL.faint))
            .textFieldStyle(.plain)
            .font(mono ? .system(size: 11, design: .monospaced) : HL.font(12))
            .foregroundStyle(HL.text)
            .padding(.vertical, 6)
            .overlay(alignment: .bottom) { Rectangle().fill(HL.line).frame(height: 1) }
    }

    private func option<C: View>(_ title: String, @ViewBuilder _ control: () -> C) -> some View {
        HStack {
            Text(title).font(HL.font(12)).foregroundStyle(HL.muted)
            Spacer()
            control().labelsHidden().fixedSize()
        }
    }
}
