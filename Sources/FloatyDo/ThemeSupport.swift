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
    case theme5 = "nasaOrange"
    case theme6 = "barbie"
    case theme7 = "matcha"
    case theme8 = "theme5"

    public static let allCases: [BuiltInTheme] = catalog.map(\.theme)

    public static let catalog: [BuiltInThemeDefinition] = [
        BuiltInThemeDefinition(
            theme: .theme1,
            style: BuiltInThemeStyle(
                backgroundColor: ThemeColor(hex: "#14141F"),
                highlightColor: ThemeColor(hex: "#454554"),
                foregroundColor: ThemeColor(hex: "#FFFFFF")
            ),
            supportsPrimaryAppIcon: true
        ),
        BuiltInThemeDefinition(
            theme: .theme2,
            style: BuiltInThemeStyle(
                backgroundColor: ThemeColor(hex: "#1B2130"),
                highlightColor: ThemeColor(hex: "#3E475C"),
                foregroundColor: ThemeColor(hex: "#FFFFFF")
            ),
            supportsPrimaryAppIcon: true
        ),
        BuiltInThemeDefinition(
            theme: .theme3,
            style: BuiltInThemeStyle(
                backgroundColor: ThemeColor(hex: "#1F2724"),
                highlightColor: ThemeColor(hex: "#3A4943"),
                foregroundColor: ThemeColor(hex: "#FFFFFF")
            ),
            supportsPrimaryAppIcon: true
        ),
        BuiltInThemeDefinition(
            theme: .theme4,
            style: BuiltInThemeStyle(
                backgroundColor: ThemeColor(hex: "#2A1E28"),
                highlightColor: ThemeColor(hex: "#523E47"),
                foregroundColor: ThemeColor(hex: "#FFFFFF")
            ),
            supportsPrimaryAppIcon: true
        ),
        BuiltInThemeDefinition(
            theme: .theme5,
            style: BuiltInThemeStyle(
                backgroundColor: ThemeColor(hex: "#DCEFFC"),
                highlightColor: ThemeColor(hex: "#B6D9F0"),
                foregroundColor: ThemeColor(hex: "#092539")
            ),
            supportsPrimaryAppIcon: false
        ),
        BuiltInThemeDefinition(
            theme: .theme6,
            style: BuiltInThemeStyle(
                backgroundColor: ThemeColor(hex: "#F2D1E1"),
                highlightColor: ThemeColor(hex: "#E9B7CF"),
                foregroundColor: ThemeColor(hex: "#240313")
            ),
            supportsPrimaryAppIcon: false
        ),
        BuiltInThemeDefinition(
            theme: .theme7,
            style: BuiltInThemeStyle(
                backgroundColor: ThemeColor(hex: "#CFDDB5"),
                highlightColor: ThemeColor(hex: "#BAC99F"),
                foregroundColor: ThemeColor(hex: "#1E2E00")
            ),
            supportsPrimaryAppIcon: false
        ),
        BuiltInThemeDefinition(
            theme: .theme8,
            style: BuiltInThemeStyle(
                backgroundColor: ThemeColor(hex: "#E6E0D6"),
                highlightColor: ThemeColor(hex: "#D3CBBE"),
                foregroundColor: ThemeColor(hex: "#41392B")
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
            colorDistance(between: resolved, and: lhs.color)
                < colorDistance(between: resolved, and: rhs.color)
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
    public let highlightColor: ThemeColor
    public let foregroundColor: ThemeColor
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
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(
            of: "#", with: "")
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
        let highlight: NSColor
        let foreground: NSColor
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

            return
                (0.2126 * linearized(color.redComponent) + 0.7152 * linearized(color.greenComponent)
                + 0.0722 * linearized(color.blueComponent))
        }
    }
#endif
