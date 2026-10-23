import SwiftUI

// MARK: - Design Tokens (§37 spec: Design Tokens Reference, prototype values)

enum DesignTokens {
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let s: CGFloat = 6
        static let m: CGFloat = 10
        static let l: CGFloat = 14
        static let xl: CGFloat = 20
    }

    enum Motion {
        static let fast: Double = 0.15
        static let base: Double = 0.22
        static let slow: Double = 0.3
        static let reveal: Double = 0.5

        static let navigation = Animation.spring(response: 0.32, dampingFraction: 0.88)
        static let entrance = Animation.easeOut(duration: 0.4)
    }

    enum Layout {
        static let sidebarWidth: CGFloat = 220
        static let inspectorWidth: CGFloat = 320
        static let onboardingWidth: CGFloat = 540
    }
}

// MARK: - Explore spectrum
//
// A fixed, deterministic multi-hue palette for explorer chrome and file-kind
// chips. Every use is paired with a label, icon or numeric value, so color is
// never the only way to distinguish two states.

extension DesignTokens {
    enum Spectrum {
        static let colors: [Color] = [
            Color(hex: 0x4C9FFF), // azure
            Color(hex: 0xB48CFF), // violet
            Color(hex: 0xF06BC8), // magenta
            Color(hex: 0xFF9F45), // orange
            Color(hex: 0xFFD166), // amber
            Color(hex: 0xA8E063), // lime
            Color(hex: 0x4ADE80), // green
            Color(hex: 0x2DD4BF), // teal
            Color(hex: 0x22D3EE), // cyan
            Color(hex: 0xFF7A8A), // rose
            Color(hex: 0x818CF8), // indigo
            Color(hex: 0xFF8A65)  // coral
        ]

        static func color(at index: Int) -> Color {
            let count = colors.count
            return colors[((index % count) + count) % count]
        }

        /// Stable across launches, unlike `String.hashValue`, so a given file
        /// extension keeps the same chip color between sessions.
        static func color(for key: String) -> Color {
            var total = 0
            for scalar in key.unicodeScalars { total = (total &* 31 &+ Int(scalar.value)) & 0x7FFF_FFFF }
            return color(at: total)
        }
    }
}

// MARK: - Category colors (spec §05 treemap color mapping)

extension Color {
    static let categoryApplications = Color(hex: 0x5B8DEF)
    static let categorySystem = Color(hex: 0x9B7BDB)
    static let categoryUserData = Color(hex: 0x50E3C2)
    static let categoryCaches = Color(hex: 0xF5A623)
    static let categoryLogs = Color(hex: 0x7ED321)
    static let categoryStale = Color(hex: 0xE8575A)
    static let categoryDuplicates = Color(hex: 0xBD10E0)
    static let categoryOther = Color(hex: 0x9B9B9B)

    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b, opacity: opacity)
    }
}
