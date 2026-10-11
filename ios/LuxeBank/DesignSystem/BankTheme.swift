import SwiftUI

/// Porcelain Titanium design tokens (light theme only — spec D10, NFR-11).
enum BankTheme {
    // MARK: Surfaces
    static let porcelain = Color(hex: 0xF3F4F7)
    static let surface = Color.white
    static let surfaceSunken = Color(hex: 0xF8F9FB)
    static let segmentTrack = Color(hex: 0xE6E9EF)
    static let line = Color(hex: 0xECEEF3)
    static let lineStrong = Color(hex: 0xE3E6EC)

    // MARK: Text
    // Every text colour passes WCAG AA (4.5:1) on the surfaces it is used on (NFR-09, ThemeContrastTests).
    static let ink = Color(hex: 0x0E1116)
    static let secondaryText = Color(hex: 0x5B6270)
    static let fractionText = Color(hex: 0x6A707C)

    // MARK: Accent & status
    static let accent = Color(hex: 0x2F5BD3)
    static let accentSoft = Color(hex: 0x5B84F0)
    static let accentTint = Color(hex: 0xE3EBFF)
    static let positive = Color(hex: 0x1B7A50)
    static let positiveTint = Color(hex: 0xE6F4EC)
    static let negative = Color(hex: 0xC0443A)
    static let negativeTint = Color(hex: 0xFFF5F4)
    static let caution = Color(hex: 0x9A5B00)
    static let cautionTint = Color(hex: 0xFFF2DD)

    // MARK: Light effects
    static let glow = Color(red: 140 / 255, green: 175 / 255, blue: 1)
    static let shadow = Color(red: 40 / 255, green: 60 / 255, blue: 110 / 255)

    static let silver = LinearGradient(
        colors: [.white, Color(hex: 0xDDE1E8), Color(hex: 0xC3C9D3)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let titanium = LinearGradient(
        colors: [Color(hex: 0xFAFBFC), Color(hex: 0xDDE1E8), Color(hex: 0xAEB5C1)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: Layout
    enum Radius {
        static let hero: CGFloat = 32
        static let card: CGFloat = 28
        static let tile: CGFloat = 16
        static let button: CGFloat = 18
        static let field: CGFloat = 16
    }

    enum Spacing {
        static let screen: CGFloat = 20
        static let section: CGFloat = 22
        static let tabBarClearance: CGFloat = 120
    }
}

/// Thonburi system font (spec D15), scaled with Dynamic Type (NFR-09).
/// Thonburi ships Light, Regular and Bold faces only.
enum BankFont {
    /// Big numbers; smaller ones (e.g. the satang part) scale with a smaller text style so Dynamic Type
    /// grows them in step with the text around them (NFR-09).
    static func figure(_ size: CGFloat) -> Font {
        let style: Font.TextStyle = size >= 34 ? .largeTitle : size >= 22 ? .title : .title3
        return .custom("Thonburi", size: size, relativeTo: style).weight(.bold)
    }

    static func title(_ size: CGFloat = 26) -> Font {
        .custom("Thonburi", size: size, relativeTo: .title).weight(.bold)
    }

    static func headline(_ size: CGFloat = 17) -> Font {
        .custom("Thonburi", size: size, relativeTo: .headline).weight(.bold)
    }

    static func body(_ size: CGFloat = 15, bold: Bool = false) -> Font {
        .custom("Thonburi", size: size, relativeTo: .body).weight(bold ? .bold : .regular)
    }

    static func caption(_ size: CGFloat = 13, bold: Bool = false) -> Font {
        .custom("Thonburi", size: size, relativeTo: .caption).weight(bold ? .bold : .regular)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
