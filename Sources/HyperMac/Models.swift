// Data models and number formatting.

import SwiftUI

// MARK: - Models

struct Position: Identifiable {
    var id: String { coin }
    let coin: String
    let side: String            // "long" | "short"
    let size, entry, mark, value, upnl, roe, funding, margin: Double
    let leverage: Int?
    let marginMode: String      // "cross" | "isolated"
    let liq, liqDistance, tp, sl: Double?
}

struct SpotRow: Identifiable {
    var id: String { coin }
    let coin: String
    let amount, price, value: Double
    let pnl, pnlPct: Double?
}

struct OrderRow: Identifiable {
    var id: String { "\(coin)-\(side)-\(price)-\(size)-\(type)-\(trigger ?? 0)" }
    let coin, side, type: String
    let size, price: Double
    let trigger: Double?
    let reduceOnly: Bool
}

struct Series {
    let t, value, pnl: [Double]
}

struct Snapshot {
    let address: String
    let updated, total, pnlDay, pnlDayPct, pnlMonth, upnl: Double
    let perpEquity, spotValue, vaultValue, stakedHype, stakedValue, hypePrice, evmHype: Double
    let withdrawable, marginUsed, notional, leverage: Double
    let minLiqDistance: Double?
    let positions: [Position]
    let spot: [SpotRow]
    let orders: [OrderRow]
    let history: [String: Series]
}

struct WalletEntry: Codable, Identifiable, Hashable {
    var id: String { address }
    var label: String
    var address: String
}

struct Config: Codable {
    var wallets: [WalletEntry] = []
    var active: Int = 0
    var refresh: Int = 15
}

// MARK: - Formatting

enum Fmt {
    static func usd(_ x: Double, signed: Bool = false, cents: Bool = true, hide: Bool = false,
                    forceCents: Bool = false) -> String {
        if hide { return "$•••••" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = cents ? 2 : 0
        f.maximumFractionDigits = cents ? (abs(x) < 1 && x != 0 && !forceCents ? 4 : 2) : 0
        let body = f.string(from: NSNumber(value: abs(x))) ?? "0"
        let sign = x < 0 ? "-" : (signed && x > 0 ? "+" : "")
        return "\(sign)$\(body)"
    }

    static func compact(_ x: Double, signed: Bool = false, hide: Bool = false) -> String {
        if hide { return "$•••" }
        let a = abs(x)
        let sign = x < 0 ? "-" : (signed && x > 0 ? "+" : "")
        if a >= 1e9 { return sign + String(format: "$%.2fB", a / 1e9) }
        if a >= 1e6 { return sign + String(format: "$%.2fM", a / 1e6) }
        if a >= 1e5 { return sign + String(format: "$%.1fK", a / 1e3) }
        return usd(x, signed: signed, cents: a < 1000)
    }

    static func pct(_ x: Double?, signed: Bool = true) -> String {
        guard let x else { return "—" }
        if abs(x) >= 10 { return signed ? (x > 0 ? ">+999%" : "<-999%") : ">999%" }
        return String(format: signed ? "%+.2f%%" : "%.1f%%", x * 100)
    }

    static func price(_ x: Double?) -> String {
        guard let x, x != 0 else { return "—" }
        if x >= 1000 {
            return String(format: x.rounded() == x ? "%.0f" : "%.1f", x).withThousands
        }
        if x >= 100 { return String(format: "%.2f", x) }
        if x >= 1 { return String(format: "%.4g", x) }
        return String(format: "%.5g", x)
    }

    static func amount(_ x: Double) -> String {
        if x >= 1000 { return String(format: "%.2f", x).withThousands }
        return String(format: x < 1 ? "%.6g" : "%.4g", x)
    }

    static func short(_ addr: String) -> String {
        guard addr.count > 10 else { return addr }
        return "\(addr.prefix(6))…\(addr.suffix(4))"
    }
}

extension String {
    var withThousands: String {
        let parts = split(separator: ".", maxSplits: 1)
        guard let whole = parts.first, let n = Int(whole) else { return self }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        let w = f.string(from: NSNumber(value: n)) ?? String(whole)
        return parts.count > 1 ? "\(w).\(parts[1])" : w
    }
}

func pnlColor(_ x: Double) -> Color { x > 0 ? HL.up : (x < 0 ? HL.down : HL.muted) }

