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
    }

    enum Layout {
        static let sidebarWidth: CGFloat = 220
        static let inspectorWidth: CGFloat = 320
        static let onboardingWidth: CGFloat = 540
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
