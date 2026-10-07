// App state: saved wallets, the latest snapshot, and the refresh timer.

import AppKit
import SwiftUI

@MainActor
final class Store: ObservableObject {
    @Published var config = Config()
    @Published var snapshot: Snapshot?
    @Published var error: String?
    @Published var loading = false

    private let defaultsKey = "config"
    private var timer: Timer?
    private var cache: [String: Snapshot] = [:]

    init() {
        loadConfig()
        schedule()
        Task { await refresh() }
    }

    var active: WalletEntry? {
        guard !config.wallets.isEmpty else { return nil }
        return config.wallets[min(max(config.active, 0), config.wallets.count - 1)]
    }

    // MARK: Persistence (UserDefaults; imports the old hl-wallet config once)

    private func loadConfig() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let cfg = try? JSONDecoder().decode(Config.self, from: data) {
            config = cfg
            return
        }
        let legacy = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config/hlwallet/config.json")
        if let data = try? Data(contentsOf: legacy), let cfg = try? JSONDecoder().decode(Config.self, from: data) {
            config = cfg
            saveConfig()
        }
    }

    private func saveConfig() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    // MARK: Refresh

    func schedule() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(max(10, config.refresh)), repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    func refresh() async {
        guard let wallet = active else {
            snapshot = nil
            return
        }
        if loading { return }
        loading = true
        defer { loading = false }
        do {
            let snap = try await Hyperliquid.snapshot(address: wallet.address)
            cache[snap.address] = snap
            if snap.address == active?.address {
                snapshot = snap
                error = nil
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: Wallets

    func select(_ w: WalletEntry) {
        guard let i = config.wallets.firstIndex(of: w) else { return }
        config.active = i
        saveConfig()
        snapshot = cache[w.address]
        Task { await refresh() }
    }

    /// Returns an error message, or nil on success.
    func addWallet(address: String, label: String) -> String? {
        let addr = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard addr.range(of: "^0x[0-9a-f]{40}$", options: .regularExpression) != nil else {
            return "Enter a public address: 0x followed by 40 hex characters. Never paste a private key."
        }
        let name = label.trimmingCharacters(in: .whitespaces)
        if let i = config.wallets.firstIndex(where: { $0.address == addr }) {
            if !name.isEmpty { config.wallets[i].label = name }
            config.active = i
        } else {
            config.wallets.append(WalletEntry(label: name.isEmpty ? "Wallet \(config.wallets.count + 1)" : name,
                                              address: addr))
            config.active = config.wallets.count - 1
        }
        saveConfig()
        snapshot = nil
        Task { await refresh() }
        return nil
    }

    func remove(_ w: WalletEntry) {
        config.wallets.removeAll { $0 == w }
        config.active = 0
        cache[w.address] = nil
        saveConfig()
        snapshot = active.flatMap { cache[$0.address] }
        Task { await refresh() }
    }

    func setRefresh(_ seconds: Int) {
        config.refresh = seconds
        saveConfig()
        schedule()
    }

    func openExplorer() {
        guard let a = active?.address,
              let url = URL(string: "https://app.hyperliquid.xyz/explorer/address/\(a)") else { return }
        NSWorkspace.shared.open(url)
    }
}
