import Foundation
#if canImport(AppKit)
import AppKit
#endif

public enum AnimationPreset: String, Codable, CaseIterable {
    case snappy
    case balanced
    case relaxed

    public var displayName: String {
        switch self {
        case .snappy:
            return "Snappy"
        case .balanced:
            return "Balanced"
        case .relaxed:
            return "Relaxed"
        }
    }

    var motion: MotionProfile {
        switch self {
        case .snappy:
            return MotionProfile(
                completionSweep: 0.18,
                checkSwapDelay: 0.08,
                completionSettle: 0.42,
                collapse: 0.24,
                dragReorder: 0.12,
                hoverFade: 0.10,
                windowSnap: 0.18
            )
        case .balanced:
            return MotionProfile(
                completionSweep: 0.25,
                checkSwapDelay: 0.10,
                completionSettle: 0.60,
                collapse: 0.35,
                dragReorder: 0.16,
                hoverFade: 0.14,
                windowSnap: 0.22
            )
        case .relaxed:
            return MotionProfile(
                completionSweep: 0.32,
                checkSwapDelay: 0.12,
                completionSettle: 0.76,
                collapse: 0.42,
                dragReorder: 0.20,
                hoverFade: 0.18,
                windowSnap: 0.28
            )
        }
    }
}

public struct MotionProfile: Equatable {
    public let completionSweep: TimeInterval
    public let checkSwapDelay: TimeInterval
    public let completionSettle: TimeInterval
    public let collapse: TimeInterval
    public let dragReorder: TimeInterval
    public let hoverFade: TimeInterval
    public let windowSnap: TimeInterval
}

public enum FontStylePreset: String, Codable, CaseIterable {
    case system
    case rounded
    case serif
    case monospaced

    public var displayName: String {
        switch self {
        case .system:
            return "System"
        case .rounded:
            return "Rounded"
        case .serif:
            return "Serif"
        case .monospaced:
            return "Monospaced"
        }
    }
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

public struct AppPreferences: Codable, Equatable {
    public var rowHeight: Double
    public var panelWidth: Double
    public var hoverHighlightsEnabled: Bool
    public var animationPreset: AnimationPreset
    public var snapPadding: Double
    public var themeColor: ThemeColor
    public var fontStyle: FontStylePreset
    public var fontSize: Double
    public var cornerRadius: Double

    private enum CodingKeys: String, CodingKey {
        case rowHeight
        case panelWidth
        case hoverHighlightsEnabled
        case animationPreset
        case snapPadding
        case themeColor
        case fontStyle
        case fontSize
        case cornerRadius
    }

    public static let `default` = AppPreferences(
        rowHeight: 36,
        panelWidth: 400,
        hoverHighlightsEnabled: true,
        animationPreset: .balanced,
        snapPadding: 32,
        themeColor: .default,
        fontStyle: .system,
        fontSize: LayoutMetrics.defaultFontSize,
        cornerRadius: 10
    )

    public init(
        rowHeight: Double,
        panelWidth: Double,
        hoverHighlightsEnabled: Bool,
        animationPreset: AnimationPreset,
        snapPadding: Double,
        themeColor: ThemeColor = .default,
        fontStyle: FontStylePreset = .system,
        fontSize: Double = 13,
        cornerRadius: Double = 10
    ) {
        self.rowHeight = rowHeight
        self.panelWidth = panelWidth
        self.hoverHighlightsEnabled = hoverHighlightsEnabled
        self.animationPreset = animationPreset
        self.snapPadding = snapPadding
        self.themeColor = themeColor
        self.fontStyle = fontStyle
        self.fontSize = fontSize
        self.cornerRadius = cornerRadius
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = AppPreferences.default

        rowHeight = try container.decodeIfPresent(Double.self, forKey: .rowHeight) ?? fallback.rowHeight
        panelWidth = try container.decodeIfPresent(Double.self, forKey: .panelWidth) ?? fallback.panelWidth
        hoverHighlightsEnabled = try container.decodeIfPresent(Bool.self, forKey: .hoverHighlightsEnabled) ?? fallback.hoverHighlightsEnabled
        animationPreset = try container.decodeIfPresent(AnimationPreset.self, forKey: .animationPreset) ?? fallback.animationPreset
        snapPadding = try container.decodeIfPresent(Double.self, forKey: .snapPadding) ?? fallback.snapPadding
        themeColor = try container.decodeIfPresent(ThemeColor.self, forKey: .themeColor) ?? fallback.themeColor
        fontStyle = try container.decodeIfPresent(FontStylePreset.self, forKey: .fontStyle) ?? fallback.fontStyle
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? fallback.fontSize
        cornerRadius = try container.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? fallback.cornerRadius
    }

    var motion: MotionProfile { animationPreset.motion }
}

#if canImport(AppKit)
struct ThemePalette {
    let background: NSColor
    let highlight: NSColor
    let text: NSColor
    let usesLightText: Bool
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

private extension NSColor {
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

    func blended(toward other: NSColor, amount: CGFloat) -> NSColor {
        let lhs = resolvedSRGB
        let rhs = other.resolvedSRGB
        let factor = min(max(amount, 0), 1)

        return NSColor(
            srgbRed: lhs.redComponent + ((rhs.redComponent - lhs.redComponent) * factor),
            green: lhs.greenComponent + ((rhs.greenComponent - lhs.greenComponent) * factor),
            blue: lhs.blueComponent + ((rhs.blueComponent - lhs.blueComponent) * factor),
            alpha: lhs.alphaComponent + ((rhs.alphaComponent - lhs.alphaComponent) * factor)
        )
    }

    func shiftedHSB(
        hueOffset: CGFloat = 0,
        saturationMultiplier: CGFloat = 1,
        brightnessMultiplier: CGFloat = 1,
        brightnessDelta: CGFloat = 0,
        brightnessOverride: CGFloat? = nil
    ) -> NSColor {
        let color = resolvedSRGB.usingColorSpace(.deviceRGB) ?? resolvedSRGB
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        let shiftedHue = hueOffset == 0
            ? hue
            : ((hue + hueOffset).truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)
        let shiftedSaturation = min(max(saturation * saturationMultiplier, 0), 1)
        let shiftedBrightness = min(
            max(brightnessOverride ?? ((brightness * brightnessMultiplier) + brightnessDelta), 0),
            1
        )

        return NSColor(
            hue: shiftedHue,
            saturation: shiftedSaturation,
            brightness: shiftedBrightness,
            alpha: alpha
        )
    }
}

extension FontStylePreset {
    func font(ofSize size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)

        switch self {
        case .system:
            return base
        case .rounded:
            if let descriptor = base.fontDescriptor.withDesign(.rounded),
               let font = NSFont(descriptor: descriptor, size: size) {
                return font
            }
            return base
        case .serif:
            if let descriptor = base.fontDescriptor.withDesign(.serif),
               let font = NSFont(descriptor: descriptor, size: size) {
                return font
            }
            return base
        case .monospaced:
            return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        }
    }
}

extension AppPreferences {
    var palette: ThemePalette {
        if themeColor == .default {
            return ThemePalette(
                background: themeColor.nsColor,
                highlight: NSColor(
                    srgbRed: 42.0 / 255.0,
                    green: 42.0 / 255.0,
                    blue: 61.0 / 255.0,
                    alpha: 1.0
                ),
                text: .white,
                usesLightText: true
            )
        }

        let background = themeColor.nsColor.resolvedSRGB
        let luminance = background.relativeLuminance

        if luminance < 0.42 {
            return ThemePalette(
                background: background,
                highlight: background.shiftedHSB(
                    hueOffset: 0.012,
                    saturationMultiplier: 0.94,
                    brightnessDelta: 0.12
                ),
                text: .white,
                usesLightText: true
            )
        }

        let text = background.shiftedHSB(
            hueOffset: 0.028,
            saturationMultiplier: 0.72,
            brightnessOverride: 0.12
        )
        let highlight = background.blended(toward: text, amount: 0.14)

        return ThemePalette(
            background: background,
            highlight: highlight,
            text: text,
            usesLightText: false
        )
    }

    var panelBackgroundColor: NSColor {
        palette.background
    }

    var activeFillColor: NSColor {
        palette.highlight
    }

    var secondarySelectionFillColor: NSColor {
        panelBackgroundColor.blended(toward: activeFillColor, amount: usesLightText ? 0.55 : 0.48)
    }

    var primaryTextColor: NSColor {
        palette.text
    }

    var secondaryTextColor: NSColor {
        palette.text.withAlphaComponent(0.56)
    }

    var subtleStrokeColor: NSColor {
        palette.text.withAlphaComponent(0.15)
    }

    var strikethroughColor: NSColor {
        palette.text.withAlphaComponent(0.5)
    }

    var selectionOverlayColor: NSColor {
        palette.text.withAlphaComponent(palette.usesLightText ? 0.18 : 0.14)
    }

    var caretColor: NSColor {
        palette.text.withAlphaComponent(0.95)
    }

    var usesLightText: Bool {
        palette.usesLightText
    }

    var maximumCornerRadius: Double {
        LayoutMetrics.maximumCornerRadius(forRowHeight: rowHeight)
    }

    func appFont(weight: NSFont.Weight = .regular) -> NSFont {
        fontStyle.font(ofSize: CGFloat(fontSize), weight: weight)
    }
}
#endif

enum LayoutMetrics {
    static let minPanelWidth: Double = 320
    static let maxPanelWidth: Double = 520
    static let minRowHeight: Double = 32
    static let maxRowHeight: Double = 48
    static let fontSizeOptions: [Double] = [12, 13, 14, 15, 16]
    static let defaultFontSizeIndex = 2
    static var defaultFontSize: Double { fontSizeOptions[defaultFontSizeIndex] }
    static let minFontSize: Double = fontSizeOptions.first ?? 11
    static let maxFontSize: Double = fontSizeOptions.last ?? 16
    static let minCornerRadius: Double = 0
    static let maxCornerRadius: Double = 24
    static let rowHorizontalInset: Double = 12
    static let textInset: Double = 8
    static let rowBackgroundInset: Double = 10
    static let rowVerticalInset: Double = 2
    static let rowCornerRadius: Double = 10
    static let circleSize: Double = 18
    static let circleHitSize: Double = 24
    static let dragHandleSize: Double = 16
    static let titlebarTrailingInset: Double = 10
    static let contentTopPadding: Double = 4
    static let trafficLightTopInset: Double = 14
    static let trafficLightSpacing: Double = 6
    static let dividerHeight: Double = 0.5
    static let contentBottomPadding: Double = 16.5

    static func maximumCornerRadius(forRowHeight rowHeight: Double) -> Double {
        let visibleRowHeight = max(0, rowHeight - (rowVerticalInset * 2.0))
        return min(maxCornerRadius, visibleRowHeight / 2.0)
    }

    static func nearestFontSizeOption(to value: Double) -> Double {
        fontSizeOptions.min(by: { abs($0 - value) < abs($1 - value) }) ?? defaultFontSize
    }
}
