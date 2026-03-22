import Foundation
#if canImport(AppKit)
import AppKit
#endif

public struct BuiltInThemeDefinition: Equatable {
    public let theme: BuiltInTheme
    public let style: BuiltInThemeStyle
    public let supportsPrimaryAppIcon: Bool

    public init(
        theme: BuiltInTheme,
        style: BuiltInThemeStyle,
        supportsPrimaryAppIcon: Bool
    ) {
        self.theme = theme
        self.style = style
        self.supportsPrimaryAppIcon = supportsPrimaryAppIcon
    }
}

public enum BuiltInTheme: String, Codable, CaseIterable {
    case theme1
    case theme2
    case theme3
    case theme4
    case theme5
    case barbie
    case matcha
    case nasaOrange

    public static let allCases: [BuiltInTheme] = catalog.map(\.theme)

    public static let catalog: [BuiltInThemeDefinition] = [
        BuiltInThemeDefinition(
            theme: .theme1,
            style: BuiltInThemeStyle(
                backgroundColor: ThemeColor(hex: "#14141F"),
                selectionColor: ThemeColor(hex: "#D7DCEF"),
                selectionOpacity: 0.14,
                contentColor: ThemeColor(hex: "#FFFFFF"),
                contentOpacity: 0.94
            ),
            supportsPrimaryAppIcon: true
        ),
        BuiltInThemeDefinition(
            theme: .theme2,
            style: BuiltInThemeStyle(
                backgroundColor: ThemeColor(hex: "#1B2130"),
                selectionColor: ThemeColor(hex: "#D2DBF0"),
                selectionOpacity: 0.13,
                contentColor: ThemeColor(hex: "#F7FAFF"),
                contentOpacity: 0.92
            ),
            supportsPrimaryAppIcon: true
        ),
        BuiltInThemeDefinition(
            theme: .theme3,
            style: BuiltInThemeStyle(
                backgroundColor: ThemeColor(hex: "#1F2724"),
                selectionColor: ThemeColor(hex: "#DDE8DE"),
                selectionOpacity: 0.12,
                contentColor: ThemeColor(hex: "#F8FBF8"),
                contentOpacity: 0.92
            ),
            supportsPrimaryAppIcon: true
        ),
        BuiltInThemeDefinition(
            theme: .theme4,
            style: BuiltInThemeStyle(
                backgroundColor: ThemeColor(hex: "#2A1E28"),
                selectionColor: ThemeColor(hex: "#E7D9E5"),
                selectionOpacity: 0.14,
                contentColor: ThemeColor(hex: "#FFF9FF"),
                contentOpacity: 0.94
            ),
            supportsPrimaryAppIcon: true
        ),
        BuiltInThemeDefinition(
            theme: .nasaOrange,
            style: BuiltInThemeStyle(
                backgroundColor: ThemeColor(hex: "#DCEFFC"),
                selectionColor: ThemeColor(hex: "#1B3242"),
                selectionOpacity: 0.11,
                contentColor: ThemeColor(hex: "#182D3A"),
                contentOpacity: 0.86
            ),
            supportsPrimaryAppIcon: false
        ),
        BuiltInThemeDefinition(
            theme: .barbie,
            style: BuiltInThemeStyle(
                backgroundColor: ThemeColor(hex: "#F2D1E1"),
                selectionColor: ThemeColor(hex: "#2D1B23"),
                selectionOpacity: 0.11,
                contentColor: ThemeColor(hex: "#2A1820"),
                contentOpacity: 0.86
            ),
            supportsPrimaryAppIcon: false
        ),
        BuiltInThemeDefinition(
            theme: .matcha,
            style: BuiltInThemeStyle(
                backgroundColor: ThemeColor(hex: "#B6C59A"),
                selectionColor: ThemeColor(hex: "#171B14"),
                selectionOpacity: 0.10,
                contentColor: ThemeColor(hex: "#141713"),
                contentOpacity: 0.84
            ),
            supportsPrimaryAppIcon: false
        ),
        BuiltInThemeDefinition(
            theme: .theme5,
            style: BuiltInThemeStyle(
                backgroundColor: ThemeColor(hex: "#E6E0D6"),
                selectionColor: ThemeColor(hex: "#17181C"),
                selectionOpacity: 0.11,
                contentColor: ThemeColor(hex: "#111112"),
                contentOpacity: 0.82
            ),
            supportsPrimaryAppIcon: true
        ),
    ]

    private static let catalogByTheme: [BuiltInTheme: BuiltInThemeDefinition] = Dictionary(
        uniqueKeysWithValues: catalog.map { ($0.theme, $0) }
    )

    public var definition: BuiltInThemeDefinition {
        guard let definition = Self.catalogByTheme[self] else {
            preconditionFailure("Missing theme definition for \(rawValue)")
        }
        return definition
    }

    public var style: BuiltInThemeStyle {
        definition.style
    }

    public var supportsPrimaryAppIcon: Bool {
        definition.supportsPrimaryAppIcon
    }

    public var color: ThemeColor {
        style.backgroundColor
    }

    public static func nearest(to color: ThemeColor) -> BuiltInTheme {
        let resolved = color.clamped()
        return allCases.min(by: { lhs, rhs in
            colorDistance(between: resolved, and: lhs.color) < colorDistance(between: resolved, and: rhs.color)
        }) ?? allCases.first ?? .theme1
    }

    private static func colorDistance(between lhs: ThemeColor, and rhs: ThemeColor) -> Double {
        let dr = lhs.red - rhs.red
        let dg = lhs.green - rhs.green
        let db = lhs.blue - rhs.blue
        return (dr * dr) + (dg * dg) + (db * db)
    }
}

public struct BuiltInThemeStyle: Equatable {
    public let backgroundColor: ThemeColor
    public let selectionColor: ThemeColor
    public let selectionOpacity: Double
    public let contentColor: ThemeColor
    public let contentOpacity: Double
}

public struct ThemeColor: Codable, Equatable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public static let `default` = ThemeColor(
        red: 0.07843137,
        green: 0.07843137,
        blue: 0.12156863,
        alpha: 1.0
    )

    public init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    func clamped() -> ThemeColor {
        ThemeColor(
            red: min(max(red, 0), 1),
            green: min(max(green, 0), 1),
            blue: min(max(blue, 0), 1),
            alpha: min(max(alpha, 0), 1)
        )
    }
}

extension ThemeColor {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        let scanner = Scanner(string: cleaned)
        var value: UInt64 = 0
        scanner.scanHexInt64(&value)

        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: 1.0)
    }
}

#if canImport(AppKit)
struct ThemePalette {
    let background: NSColor
    let selectionColor: NSColor
    let selectionOpacity: CGFloat
    let contentColor: NSColor
    let contentOpacity: CGFloat
    let usesLightText: Bool
}

extension ThemeColor {
    init(nsColor: NSColor) {
        let color = nsColor.usingColorSpace(.deviceRGB) ?? nsColor
        self.init(
            red: Double(color.redComponent),
            green: Double(color.greenComponent),
            blue: Double(color.blueComponent),
            alpha: Double(color.alphaComponent)
        )
    }

    var nsColor: NSColor {
        NSColor(
            srgbRed: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: CGFloat(alpha)
        )
    }
}

extension NSColor {
    var resolvedSRGB: NSColor {
        usingColorSpace(.sRGB) ?? usingColorSpace(.deviceRGB) ?? self
    }

    var relativeLuminance: CGFloat {
        let color = resolvedSRGB

        func linearized(_ component: CGFloat) -> CGFloat {
            component <= 0.03928 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }

        return (
            0.2126 * linearized(color.redComponent) +
            0.7152 * linearized(color.greenComponent) +
            0.0722 * linearized(color.blueComponent)
        )
    }
}
#endif
