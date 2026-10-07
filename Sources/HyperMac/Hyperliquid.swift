// Read-only Hyperliquid client. Only public "info" endpoints are used — no keys, no signing.

import Foundation

struct HLError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum Hyperliquid {
    static let infoURL = URL(string: "https://api.hyperliquid.xyz/info")!
    static let evmURL = URL(string: "https://rpc.hyperliquid.xyz/evm")!
    static let stables: Set<String> = ["USDC", "USDT0", "USDH", "USDE", "USDHL", "FEUSD", "USDXL"]

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 12
        c.httpAdditionalHeaders = ["User-Agent": "HyperMac/\(appVersion)", "Content-Type": "application/json"]
        return URLSession(configuration: c)
    }()

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    static func post(_ url: URL, _ body: [String: Any]) async throws -> Any {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        var last: Error = HLError("Can't reach Hyperliquid")
        for attempt in 1...3 {
            do {
                let (data, resp) = try await session.data(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if code == 429 {
                    last = HLError("Hyperliquid rate limit — slowing down")
                    try await Task.sleep(nanoseconds: UInt64(attempt) * 1_500_000_000)
                    continue
                }
                guard (200..<300).contains(code) else { throw HLError("Hyperliquid returned HTTP \(code)") }
                return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            } catch let e as HLError {
                throw e
            } catch {
                last = HLError("Can't reach Hyperliquid (\(error.localizedDescription))")
                try? await Task.sleep(nanoseconds: UInt64(attempt) * 400_000_000)
            }
        }
        throw last
    }

    static func info(_ body: [String: Any]) async throws -> Any { try await post(infoURL, body) }

    // MARK: Snapshot

    static func snapshot(address raw: String) async throws -> Snapshot {
        let a = raw.lowercased()
        let market = await Market.shared.load()

        async let spotR = try? info(["type": "spotClearinghouseState", "user": a])
        async let portR = try? info(["type": "portfolio", "user": a])
        async let midsR = try? info(["type": "allMids"])
        async let stakeR = try? info(["type": "delegatorSummary", "user": a])
        async let vaultR = try? info(["type": "userVaultEquities", "user": a])
        async let evmR = try? post(evmURL, ["jsonrpc": "2.0", "id": 1, "method": "eth_getBalance",
                                            "params": [a, "latest"]])

        // perp state for the main dex and every HIP-3 dex (e.g. xyz:NVDA)
        let perps: [String: [String: Any]] = try await withThrowingTaskGroup(of: (String, [String: Any]?).self) { g in
            for d in market.dexs {
                g.addTask {
                    var body: [String: Any] = ["type": "clearinghouseState", "user": a]
                    if !d.isEmpty { body["dex"] = d }
                    if d.isEmpty { return (d, try await info(body) as? [String: Any]) }  // main dex must succeed
                    return (d, (try? await info(body)) as? [String: Any])
                }
            }
            var out: [String: [String: Any]] = [:]
            for try await (d, st) in g { if let st { out[d] = st } }
            return out
        }

        // open orders only where there is something open (keeps request weight low)
        let orderDexs = perps.filter { $0.key.isEmpty || !(($0.value["assetPositions"] as? [Any]) ?? []).isEmpty }.keys
        let rawOrders: [[String: Any]] = await withTaskGroup(of: [[String: Any]].self) { g in
            for d in orderDexs {
                g.addTask {
                    var body: [String: Any] = ["type": "frontendOpenOrders", "user": a]
                    if !d.isEmpty { body["dex"] = d }
                    return ((try? await info(body)) as? [[String: Any]]) ?? []
                }
            }
            var out: [[String: Any]] = []
            for await chunk in g { out += chunk }
            return out
        }

        let spot = (await spotR as? [String: Any]) ?? [:]
        let port = Dictionary(uniqueKeysWithValues: ((await portR as? [[Any]]) ?? []).compactMap { pair -> (String, [String: Any])? in
            guard pair.count == 2, let k = pair[0] as? String, let v = pair[1] as? [String: Any] else { return nil }
            return (k, v)
        })
        let mids = (await midsR as? [String: Any]) ?? [:]
        let stake = (await stakeR as? [String: Any]) ?? [:]
        let vaults = (await vaultR as? [[String: Any]]) ?? []
        let evm = (await evmR as? [String: Any]) ?? [:]

        func mid(_ coin: String?) -> Double { coin.map { num(mids[$0]) } ?? 0 }
        var hypePx = mid(market.hypeToken.flatMap { market.spotPair[$0] })
        if hypePx == 0 { hypePx = mid("HYPE") }

        // perps
        var positions: [Position] = []
        var perpEquity = 0.0, marginUsed = 0.0, notional = 0.0, withdrawable = 0.0
        for st in perps.values {
            let ms = st["marginSummary"] as? [String: Any] ?? [:]
            perpEquity += num(ms["accountValue"])
            marginUsed += num(ms["totalMarginUsed"])
            notional += num(ms["totalNtlPos"])
            withdrawable += num(st["withdrawable"])
            for ap in st["assetPositions"] as? [[String: Any]] ?? [] {
                guard let p = ap["position"] as? [String: Any], let coin = p["coin"] as? String else { continue }
                let size = num(p["szi"])
                if size == 0 { continue }
                let value = num(p["positionValue"])
                let mark = value / abs(size)
                let liq = optNum(p["liquidationPx"])
                let lev = p["leverage"] as? [String: Any] ?? [:]
                let triggers = rawOrders.filter { ($0["coin"] as? String) == coin && ($0["isTrigger"] as? Bool) == true }
                func nearest(_ kind: String) -> Double? {
                    triggers.filter { (($0["orderType"] as? String) ?? "").lowercased().contains(kind) }
                        .map { num($0["triggerPx"]) }
                        .min { abs($0 - mark) < abs($1 - mark) }
                }
                positions.append(Position(
                    coin: coin, side: size > 0 ? "long" : "short", size: abs(size), entry: num(p["entryPx"]),
                    mark: mark, value: value, upnl: num(p["unrealizedPnl"]), roe: num(p["returnOnEquity"]),
                    funding: -num((p["cumFunding"] as? [String: Any])?["sinceOpen"]),  // + = you earned
                    margin: num(p["marginUsed"]), leverage: (lev["value"] as? NSNumber)?.intValue,
                    marginMode: lev["type"] as? String ?? "cross", liq: liq,
                    liqDistance: liq.flatMap { mark > 0 ? abs(mark - $0) / mark : nil },
                    tp: nearest("take profit"), sl: nearest("stop")))
            }
        }
        positions.sort { $0.value > $1.value }

        // spot
        var spotRows: [SpotRow] = []
        for b in spot["balances"] as? [[String: Any]] ?? [] {
            let total = num(b["total"])
            guard total > 0, let coin = b["coin"] as? String else { continue }
            var px = stables.contains(coin) ? 1 : mid((b["token"] as? NSNumber).flatMap { market.spotPair[$0.intValue] })
            if px == 0 && coin == "HYPE" { px = hypePx }
            let value = total * px
            let entry = num(b["entryNtl"])
            let hasCost = entry > 0 && px > 0
            spotRows.append(SpotRow(coin: coin, amount: total, price: px, value: value,
                                    pnl: hasCost ? value - entry : nil, pnlPct: hasCost ? (value - entry) / entry : nil))
        }
        spotRows.sort { $0.value > $1.value }
        let spotValue = spotRows.reduce(0) { $0 + $1.value }

        // staking, vaults, HyperEVM
        let staked = num(stake["delegated"]) + num(stake["undelegated"]) + num(stake["totalPendingWithdrawal"])
        let vaultValue = vaults.map { num($0["equity"]) }.filter { $0 >= 0.01 }.reduce(0, +)
        let evmHype = (evm["result"] as? String).flatMap { weiToEther($0) } ?? 0

        // history + headline numbers from Hyperliquid's own portfolio series (matches the website)
        func series(_ key: String) -> Series {
            let v = port[key] ?? [:]
            let vals = v["accountValueHistory"] as? [[Any]] ?? []
            let pnls = v["pnlHistory"] as? [[Any]] ?? []
            return Series(t: vals.map { num($0.first) / 1000 }, value: vals.map { num($0.last) },
                          pnl: Array(pnls.map { num($0.last) }.prefix(vals.count)))
        }
        var history: [String: Series] = [:]
        for k in ["day", "week", "month", "allTime"] { history[k] = series(k) }
        func change(_ k: String) -> Double {
            guard let p = history[k]?.pnl, p.count >= 2 else { return 0 }
            return p.last! - p.first!
        }
        let total = history["allTime"]?.value.last ?? (perpEquity + spotValue + vaultValue)
        let pnlDay = change("day")
        let start = total - pnlDay

        return Snapshot(
            address: a, updated: Date().timeIntervalSince1970, total: total, pnlDay: pnlDay,
            pnlDayPct: start > 0 ? pnlDay / start : 0, pnlMonth: change("month"),
            upnl: positions.reduce(0) { $0 + $1.upnl },
            perpEquity: perpEquity, spotValue: spotValue, vaultValue: vaultValue, stakedHype: staked,
            stakedValue: staked * hypePx, hypePrice: hypePx, evmHype: evmHype, withdrawable: withdrawable,
            marginUsed: marginUsed, notional: notional, leverage: perpEquity > 0 ? notional / perpEquity : 0,
            minLiqDistance: positions.compactMap(\.liqDistance).min(),
            positions: positions, spot: spotRows,
            orders: rawOrders.map { o in
                OrderRow(coin: o["coin"] as? String ?? "?", side: (o["side"] as? String) == "B" ? "buy" : "sell",
                         type: o["orderType"] as? String ?? "", size: num(o["sz"]), price: num(o["limitPx"]),
                         trigger: (o["isTrigger"] as? Bool) == true ? num(o["triggerPx"]) : nil,
                         reduceOnly: o["reduceOnly"] as? Bool ?? false)
            },
            history: history)
    }

    // MARK: Helpers

    static func num(_ x: Any?) -> Double {
        if let s = x as? String { return Double(s) ?? 0 }
        if let n = x as? NSNumber { return n.doubleValue }
        return 0
    }

    static func optNum(_ x: Any?) -> Double? {
        guard let x, !(x is NSNull) else { return nil }
        let v = num(x)
        return v == 0 ? nil : v
    }

    /// "0x1b1ae4d6e2ef500000" → 0.5 (18 decimals), without overflowing for large balances.
    static func weiToEther(_ hex: String) -> Double {
        var value = 0.0
        for ch in hex.lowercased().dropFirst(2) {
            guard let d = ch.hexDigitValue else { return 0 }
            value = value * 16 + Double(d)
        }
        return value / 1e18
    }
}

/// Market metadata that rarely changes: perp dex list and spot token → USDC pair.
actor Market {
    static let shared = Market()

    struct Info {
        var dexs: [String] = [""]
        var spotPair: [Int: String] = [:]   // token index → allMids key
        var hypeToken: Int?
    }

    private var cached = Info()
    private var loaded = Date.distantPast

    func load() async -> Info {
        if Date().timeIntervalSince(loaded) < 3600 { return cached }
        async let dexsR = try? Hyperliquid.info(["type": "perpDexs"])
        async let metaR = try? Hyperliquid.info(["type": "spotMeta"])
        var info = Info()
        if let list = await dexsR as? [Any] {
            info.dexs = [""] + list.compactMap { ($0 as? [String: Any])?["name"] as? String }
        }
        if let meta = await metaR as? [String: Any] {
            let tokens = meta["tokens"] as? [[String: Any]] ?? []
            let usdc = tokens.first { ($0["name"] as? String) == "USDC" }.flatMap { ($0["index"] as? NSNumber)?.intValue } ?? 0
            info.hypeToken = tokens.first { ($0["name"] as? String) == "HYPE" }.flatMap { ($0["index"] as? NSNumber)?.intValue }
            for u in meta["universe"] as? [[String: Any]] ?? [] {
                guard let pair = u["tokens"] as? [NSNumber], pair.count == 2, let name = u["name"] as? String,
                      pair[1].intValue == usdc else { continue }
                let base = pair[0].intValue
                if info.spotPair[base] == nil || (u["isCanonical"] as? Bool) == true { info.spotPair[base] = name }
            }
            cached = info
            loaded = Date()
        }
        return info.spotPair.isEmpty ? cached : info
    }
}
