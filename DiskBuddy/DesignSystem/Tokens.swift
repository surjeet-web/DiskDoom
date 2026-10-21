import SwiftUI

// MARK: - Shared industrial materials, spacing, geometry and motion

enum DesignTokens {
    enum Palette {
        static let void = Color(hex: 0x080B0F)
        static let app = Color(hex: 0x0B0E13)
        static let panel = Color(hex: 0x10151A)
        static let raised = Color(hex: 0x181E23)
        static let steel = Color(hex: 0x53616B)
        static let rim = Color(hex: 0x8598A5)
        static let text = Color(hex: 0xF1F5F7)
        static let muted = Color(hex: 0x9CA7B1)
        static let orange = Color(hex: 0xFF6923)
        static let cyan = Color(hex: 0x22C8FC)
        static let violet = Color(hex: 0xA96AFF)
        static let teal = Color(hex: 0x2EE28A)
        static let red = Color(hex: 0xFF897D)
        static let blue = Color(hex: 0x168BFF)
        static let amber = Color(hex: 0xF8AA53)
    }

    enum Geometry {
        static let smallCut: CGFloat = 8
        static let cut: CGFloat = 16
        static let largeCut: CGFloat = 24
        static let depth: CGFloat = 4
        static let safeInset: CGFloat = 24
    }
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

// MARK: - Category colors (spec §05 treemap color mapping)

extension Color {
    static let categoryApplications = Color(hex: 0x9051DB)
    static let categorySystem = Color(hex: 0x566777)
    static let categoryUserData = Color(hex: 0x23B2FF)
    static let categoryCaches = Color(hex: 0xFFA047)
    static let categoryLogs = Color(hex: 0x36E9A4)
    static let categoryStale = Color(hex: 0xFF897D)
    static let categoryDuplicates = Color(hex: 0xD69AFF)
    static let categoryOther = Color(hex: 0x859DAF)

    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b, opacity: opacity)
    }
}
