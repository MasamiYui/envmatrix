import SwiftUI
import AppKit

/// Semantic fills shared by cards, chips and rows.
///
/// These are dynamic NSColors, so they pick a black-based tint in Light
/// mode and a white-based tint in Dark mode. The previous ad-hoc
/// `Color.gray.opacity(…)` / `Color.secondary.opacity(…)` recipes produced
/// muddy, low-contrast surfaces on dark backgrounds and drifted between
/// files (0.06, 0.08, 0.12, 0.18…).
public extension Color {
    /// Background for grouped rows, preset cards and inline code chips.
    static let subtleFill = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDark ? NSColor.white.withAlphaComponent(0.07)
                          : NSColor.black.withAlphaComponent(0.05)
    })

    /// Slightly stronger fill for capsules, tags and stat chips.
    static let chipFill = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDark ? NSColor.white.withAlphaComponent(0.13)
                          : NSColor.black.withAlphaComponent(0.09)
    })

    /// Hairline border that stays visible on both appearances.
    static let hairline = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDark ? NSColor.white.withAlphaComponent(0.10)
                          : NSColor.black.withAlphaComponent(0.08)
    })
}

private extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
