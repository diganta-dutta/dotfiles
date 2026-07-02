// Theme.swift — the app's palette, lifted from the approved mockup so the native
// UI matches it instead of leaning on macOS system defaults. Colors that need to
// survive dark mode are defined as dynamic NSColors; the rest are fixed sRGB.

import SwiftUI
import AppKit

extension Color {
    /// 0xRRGGBB literal → sRGB Color.
    init(hex: UInt) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

/// A color that resolves differently in light vs dark appearance.
private func dynamicColor(light: UInt, dark: UInt) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                       green: CGFloat((hex >> 8) & 0xFF) / 255,
                       blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    })
}

enum Theme {
    // Brand accent + its soft/text companions (used on primary buttons, checkboxes,
    // selection, the auto-review strip, and reason tags).
    static let accent      = Color(hex: 0x0A84FF)
    static let accentText  = dynamicColor(light: 0x0A5BC4, dark: 0x6FB4FF)
    static let accentSoft  = dynamicColor(light: 0xE7F1FF, dark: 0x123252)

    // Neutrals — biased a touch cool to sit under the blue accent.
    static let ink         = dynamicColor(light: 0x1D1D1F, dark: 0xF2F2F5)
    static let ink2        = dynamicColor(light: 0x6E6E73, dark: 0xA6A6AD)
    static let ink3        = dynamicColor(light: 0x9A9AA0, dark: 0x7C7C84)

    // Surfaces.
    static let toolbarBG   = dynamicColor(light: 0xFCFCFD, dark: 0x2A2A2C)
    static let sidebarBG   = dynamicColor(light: 0xF4F5F7, dark: 0x1E1E20)

    // Semantic (verdict / run state) — distinct from the accent hue.
    static let good        = Color(hex: 0x2F9E44)   // approved / done
    static let crit        = Color(hex: 0xE03131)   // changes requested / failed
    static let warn        = Color(hex: 0xE8590C)   // re-review / tool calls
    static let commented   = accent                 // commented verdict

    // Run source badge.
    static let sourceAuto  = dynamicColor(light: 0x6B3FD4, dark: 0xB79BF5)
}
