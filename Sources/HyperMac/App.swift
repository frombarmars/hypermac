// HyperMac — your Hyperliquid account in the macOS menu bar.
// Read-only: only public addresses are used; nothing here can sign or move funds.

import AppKit
import SwiftUI

@main
struct HyperMacApp: App {
    @StateObject private var store = Store()
    @AppStorage("labelMode") private var labelMode = "total"
    @AppStorage("hideAmounts") private var hide = false

    var body: some Scene {
        MenuBarExtra {
            PanelView().environmentObject(store)
        } label: {
            HStack(spacing: 4) {
                if (store.snapshot?.minLiqDistance ?? 1) < 0.1 {
                    Image(systemName: "exclamationmark.triangle.fill")
                } else {
                    Image(nsImage: Self.menuIcon)
                }
                if labelMode != "icon", let text = labelText {
                    Text(text).monospacedDigit()
                }
            }
        }
        .menuBarExtraStyle(.window)
    }

    static let menuIcon: NSImage = {
        let img = Bundle.main.image(forResource: "MenuIcon") ?? NSImage(systemSymbolName: "drop.fill", accessibilityDescription: nil)!
        img.size = NSSize(width: 18, height: 18)
        img.isTemplate = true
        return img
    }()

    private var labelText: String? {
        guard let s = store.snapshot else { return store.active == nil ? "Add wallet" : nil }
        switch labelMode {
        case "pnl24":  // when hidden, show the percentage instead of dollars
            return hide ? Fmt.pct(s.pnlDayPct) : Fmt.usd(s.pnlDay, signed: true, cents: abs(s.pnlDay) < 1000)
        case "upnl": return Fmt.usd(s.upnl, signed: true, cents: abs(s.upnl) < 1000, hide: hide)
        default: return Fmt.compact(s.total, hide: hide)
        }
    }
}
