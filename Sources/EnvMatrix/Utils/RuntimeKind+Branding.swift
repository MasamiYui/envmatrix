import SwiftUI

/// UI-layer branding metadata for each RuntimeKind.
/// Kept out of Models/RuntimeKind.swift so the domain model stays Foundation-only.
public extension RuntimeKind {
    /// A single letter used as a fallback glyph (e.g. inside monogram badges).
    var initial: String {
        switch self {
        case .node: return "N"
        case .python: return "P"
        case .java: return "J"
        case .go: return "G"
        case .rust: return "R"
        case .ruby: return "R"
        case .php: return "P"
        case .deno: return "D"
        case .bun: return "B"
        case .dotnet: return "."
        case .erlang: return "E"
        }
    }

    /// SF Symbol icon rendered inside the branded badge on cards.
    var iconName: String {
        switch self {
        case .node: return "n.circle.fill"
        case .python: return "chevron.left.forwardslash.chevron.right"
        case .java: return "cup.and.saucer.fill"
        case .go: return "bolt.fill"
        case .rust: return "gearshape.2.fill"
        case .ruby: return "diamond.fill"
        case .php: return "curlybraces"
        case .deno: return "pawprint.fill"
        case .bun: return "leaf.fill"
        case .dotnet: return "square.stack.3d.up.fill"
        case .erlang: return "antenna.radiowaves.left.and.right"
        }
    }

    /// Primary brand tint. Approximates the widely-used identity color of each language.
    var brandColor: Color {
        switch self {
        case .node: return Color(red: 0.20, green: 0.68, blue: 0.30)   // Node green
        case .python: return Color(red: 0.22, green: 0.46, blue: 0.75) // Python blue
        case .java: return Color(red: 0.94, green: 0.42, blue: 0.15)   // Java orange
        case .go: return Color(red: 0.00, green: 0.68, blue: 0.85)     // Go cyan
        case .rust: return Color(red: 0.79, green: 0.42, blue: 0.22)   // Rust ochre
        case .ruby: return Color(red: 0.80, green: 0.16, blue: 0.20)   // Ruby red
        case .php: return Color(red: 0.47, green: 0.44, blue: 0.72)    // PHP indigo
        case .deno: return Color(red: 0.10, green: 0.10, blue: 0.12)   // Deno graphite
        case .bun: return Color(red: 0.97, green: 0.75, blue: 0.29)    // Bun cream yellow
        case .dotnet: return Color(red: 0.32, green: 0.30, blue: 0.75) // .NET violet
        case .erlang: return Color(red: 0.61, green: 0.16, blue: 0.35) // Erlang burgundy
        }
    }

    /// Gradient stops used for the icon badge background.
    var brandGradient: LinearGradient {
        LinearGradient(
            colors: [brandColor.opacity(0.95), brandColor.opacity(0.62)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
