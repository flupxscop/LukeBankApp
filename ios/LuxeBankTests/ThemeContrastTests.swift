import SwiftUI
import Testing
import UIKit
@testable import LuxeBank

/// NFR-09: text colours meet WCAG AA (4.5:1) on the backgrounds they are used on.
struct ThemeContrastTests {
    private static func luminance(_ color: Color) -> Double {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func linear(_ value: CGFloat) -> Double {
            let value = Double(value)
            return value <= 0.039_28 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    static func ratio(_ first: Color, _ second: Color) -> Double {
        let (lighter, darker) = (max(luminance(first), luminance(second)), min(luminance(first), luminance(second)))
        return (lighter + 0.05) / (darker + 0.05)
    }

    struct Pair {
        let name: String
        let text: Color
        let background: Color

        init(_ name: String, _ text: Color, _ background: Color) {
            self.name = name
            self.text = text
            self.background = background
        }
    }

    static let pairs: [Pair] = [
        Pair("ink on surface", BankTheme.ink, BankTheme.surface),
        Pair("secondary on surface", BankTheme.secondaryText, BankTheme.surface),
        Pair("secondary on porcelain", BankTheme.secondaryText, BankTheme.porcelain),
        Pair("secondary on segment track", BankTheme.secondaryText, BankTheme.segmentTrack),
        Pair("satang digits on surface", BankTheme.fractionText, BankTheme.surface),
        Pair("satang digits on porcelain", BankTheme.fractionText, BankTheme.porcelain),
        Pair("accent on surface", BankTheme.accent, BankTheme.surface),
        Pair("accent on accent tint", BankTheme.accent, BankTheme.accentTint),
        Pair("positive on surface", BankTheme.positive, BankTheme.surface),
        Pair("positive on positive tint", BankTheme.positive, BankTheme.positiveTint),
        Pair("negative on surface", BankTheme.negative, BankTheme.surface),
        Pair("negative on negative tint", BankTheme.negative, BankTheme.negativeTint),
        Pair("caution on caution tint", BankTheme.caution, BankTheme.cautionTint),
        Pair("white on ink", .white, BankTheme.ink),
        Pair("white on negative (badge)", .white, BankTheme.negative),
    ]

    @Test(arguments: pairs.indices)
    func meetsAA(index: Int) {
        let pair = Self.pairs[index]
        let ratio = Self.ratio(pair.text, pair.background)
        #expect(ratio >= 4.5, "\(pair.name): \(ratio)")
    }
}
