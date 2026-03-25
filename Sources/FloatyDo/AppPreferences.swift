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
                reflow: 0.18,
                dragReorder: 0.12,
                hoverFade: 0.10,
            )
        case .balanced:
            return MotionProfile(
                completionSweep: 0.25,
                checkSwapDelay: 0.10,
                completionSettle: 0.60,
                collapse: 0.35,
                reflow: 0.22,
                dragReorder: 0.16,
                hoverFade: 0.14
            )
        case .relaxed:
            return MotionProfile(
                completionSweep: 0.32,
                checkSwapDelay: 0.12,
                completionSettle: 0.76,
                collapse: 0.42,
                reflow: 0.28,
                dragReorder: 0.20,
                hoverFade: 0.18
            )
        }
    }
}

public struct MotionProfile: Equatable {
    public let completionSweep: TimeInterval
    public let checkSwapDelay: TimeInterval
    public let completionSettle: TimeInterval
    public let collapse: TimeInterval
    public let reflow: TimeInterval
    public let dragReorder: TimeInterval
    public let hoverFade: TimeInterval
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

public struct AppPreferences: Codable, Equatable {
    public var rowHeight: Double
    public var panelWidth: Double
    public var hoverHighlightsEnabled: Bool
    public var animationPreset: AnimationPreset
    public var snapPadding: Double
    public var theme: BuiltInTheme
    public var fontStyle: FontStylePreset
    public var fontSize: Double
    public var cornerRadius: Double
    public var blurEnabled: Bool
    public var windowOpacity: Double
    public var globalHotkey: GlobalHotkey

    private enum CodingKeys: String, CodingKey {
        case rowHeight
        case panelWidth
        case hoverHighlightsEnabled
        case animationPreset
        case snapPadding
        case theme
        case themeColor
        case fontStyle
        case fontSize
        case cornerRadius
        case blurEnabled
        case windowOpacity
        case globalHotkey
    }

    public static let `default` = AppPreferences(
        rowHeight: 36,
        panelWidth: 400,
        hoverHighlightsEnabled: true,
        animationPreset: .balanced,
        snapPadding: 32,
        theme: .theme1,
        fontStyle: .system,
        fontSize: LayoutMetrics.defaultFontSize,
        cornerRadius: 10,
        blurEnabled: true,
        windowOpacity: 1.0,
        globalHotkey: .defaultToggle
    )

    public init(
        rowHeight: Double,
        panelWidth: Double,
        hoverHighlightsEnabled: Bool,
        animationPreset: AnimationPreset,
        snapPadding: Double,
        theme: BuiltInTheme = .theme1,
        fontStyle: FontStylePreset = .system,
        fontSize: Double = 13,
        cornerRadius: Double = 10,
        blurEnabled: Bool = true,
        windowOpacity: Double = 1.0,
        globalHotkey: GlobalHotkey = .defaultToggle
    ) {
        self.rowHeight = rowHeight
        self.panelWidth = panelWidth
        self.hoverHighlightsEnabled = hoverHighlightsEnabled
        self.animationPreset = animationPreset
        self.snapPadding = snapPadding
        self.theme = theme
        self.fontStyle = fontStyle
        self.fontSize = fontSize
        self.cornerRadius = cornerRadius
        self.blurEnabled = blurEnabled
        self.windowOpacity = windowOpacity
        self.globalHotkey = globalHotkey
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = AppPreferences.default

        rowHeight = try container.decodeIfPresent(Double.self, forKey: .rowHeight) ?? fallback.rowHeight
        panelWidth = try container.decodeIfPresent(Double.self, forKey: .panelWidth) ?? fallback.panelWidth
        hoverHighlightsEnabled = try container.decodeIfPresent(Bool.self, forKey: .hoverHighlightsEnabled) ?? fallback.hoverHighlightsEnabled
        animationPreset = try container.decodeIfPresent(AnimationPreset.self, forKey: .animationPreset) ?? fallback.animationPreset
        snapPadding = try container.decodeIfPresent(Double.self, forKey: .snapPadding) ?? fallback.snapPadding
        if let decodedTheme = try container.decodeIfPresent(BuiltInTheme.self, forKey: .theme) {
            theme = decodedTheme
        } else if let legacyThemeColor = try container.decodeIfPresent(ThemeColor.self, forKey: .themeColor) {
            theme = BuiltInTheme.nearest(to: legacyThemeColor)
        } else {
            theme = fallback.theme
        }
        fontStyle = try container.decodeIfPresent(FontStylePreset.self, forKey: .fontStyle) ?? fallback.fontStyle
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? fallback.fontSize
        cornerRadius = try container.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? fallback.cornerRadius
        blurEnabled = try container.decodeIfPresent(Bool.self, forKey: .blurEnabled) ?? fallback.blurEnabled
        windowOpacity = try container.decodeIfPresent(Double.self, forKey: .windowOpacity) ?? fallback.windowOpacity
        globalHotkey = (try container.decodeIfPresent(GlobalHotkey.self, forKey: .globalHotkey) ?? fallback.globalHotkey).normalized
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rowHeight, forKey: .rowHeight)
        try container.encode(panelWidth, forKey: .panelWidth)
        try container.encode(hoverHighlightsEnabled, forKey: .hoverHighlightsEnabled)
        try container.encode(animationPreset, forKey: .animationPreset)
        try container.encode(snapPadding, forKey: .snapPadding)
        try container.encode(theme, forKey: .theme)
        try container.encode(fontStyle, forKey: .fontStyle)
        try container.encode(fontSize, forKey: .fontSize)
        try container.encode(cornerRadius, forKey: .cornerRadius)
        try container.encode(blurEnabled, forKey: .blurEnabled)
        try container.encode(windowOpacity, forKey: .windowOpacity)
        try container.encode(globalHotkey.normalized, forKey: .globalHotkey)
    }

    var motion: MotionProfile { animationPreset.motion }

    public var themeColor: ThemeColor {
        theme.color
    }
}

#if canImport(AppKit)
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
    var clampedWindowOpacity: Double {
        min(max(windowOpacity, LayoutMetrics.minWindowOpacity), 1.0)
    }

    var selectedBuiltInTheme: BuiltInTheme {
        theme
    }

    var palette: ThemePalette {
        let style = selectedBuiltInTheme.style
        let background = style.backgroundColor.nsColor.resolvedSRGB
        let contentColor = style.contentColor.nsColor.resolvedSRGB
        return ThemePalette(
            background: background,
            selectionColor: style.selectionColor.nsColor.resolvedSRGB,
            selectionOpacity: CGFloat(min(max(style.selectionOpacity, 0), 1)),
            contentColor: contentColor,
            contentOpacity: CGFloat(min(max(style.contentOpacity, 0), 1)),
            usesLightText: contentColor.relativeLuminance > background.relativeLuminance
        )
    }

    var panelBackgroundColor: NSColor {
        palette.background
    }

    var translucentSurfaceTintColor: NSColor {
        panelBackgroundColor.withAlphaComponent(translucentSurfaceOpacity)
    }

    var activeFillColor: NSColor {
        return palette.selectionColor.withAlphaComponent(palette.selectionOpacity)
    }

    var primaryTextColor: NSColor {
        resolvedContentColor()
    }

    var secondaryTextColor: NSColor {
        return resolvedContentColor(multiplier: 0.72)
    }

    var subtleStrokeColor: NSColor {
        return palette.contentColor.withAlphaComponent(max(0.12, palette.contentOpacity * 0.22))
    }

    var strikethroughColor: NSColor {
        return resolvedContentColor(multiplier: 0.60)
    }

    var selectionOverlayColor: NSColor {
        let highlightOpacity = min(max(Double(palette.selectionOpacity) + 0.08, 0.14), 0.30)
        return palette.selectionColor.withAlphaComponent(highlightOpacity)
    }

    var caretColor: NSColor {
        return palette.contentColor.withAlphaComponent(min(max(Double(palette.contentOpacity) + 0.06, 0), 1))
    }

    var usesLightText: Bool {
        return palette.usesLightText
    }

    var usesTranslucentSurface: Bool {
        blurEnabled
    }

    var contentBaseColor: NSColor {
        palette.contentColor
    }

    var translucentSurfaceOpacity: Double {
        let normalized = (clampedWindowOpacity - LayoutMetrics.minWindowOpacity) / (1.0 - LayoutMetrics.minWindowOpacity)
        let eased = pow(min(max(normalized, 0), 1), 1.35)
        return 0.03 + (0.49 * eased)
    }

    var translucentEffectAlpha: Double {
        let normalized = (clampedWindowOpacity - LayoutMetrics.minWindowOpacity) / (1.0 - LayoutMetrics.minWindowOpacity)
        let eased = pow(min(max(normalized, 0), 1), 0.85)
        return 0.90 + (0.10 * eased)
    }

    var compositedTranslucentSurfaceOpacity: Double {
        let normalized = (clampedWindowOpacity - LayoutMetrics.minWindowOpacity) / (1.0 - LayoutMetrics.minWindowOpacity)
        let eased = pow(min(max(normalized, 0), 1), 0.92)
        return 0.58 + (0.34 * eased)
    }

    var compositedTranslucentSurfaceFillColor: NSColor {
        panelBackgroundColor.withAlphaComponent(compositedTranslucentSurfaceOpacity)
    }

    var compositedTranslucentSurfaceStrokeColor: NSColor {
        let normalized = (clampedWindowOpacity - LayoutMetrics.minWindowOpacity) / (1.0 - LayoutMetrics.minWindowOpacity)
        let opacity = 0.10 + (0.08 * min(max(normalized, 0), 1))
        return contentBaseColor.withAlphaComponent(opacity)
    }

    var backdropBlurRadius: Double {
        let normalized = (clampedWindowOpacity - LayoutMetrics.minWindowOpacity) / (1.0 - LayoutMetrics.minWindowOpacity)
        let eased = min(max(normalized, 0), 1)
        return 18.0 - (8.0 * eased)
    }

    var maximumCornerRadius: Double {
        LayoutMetrics.maximumCornerRadius(forRowHeight: rowHeight)
    }

    var manualTextVerticalOffset: Double {
        LayoutMetrics.manualTextVerticalOffset(fontStyle: fontStyle, fontSize: fontSize)
    }

    var displayTextVerticalOffset: Double {
        LayoutMetrics.displayTextVerticalOffset(fontStyle: fontStyle, fontSize: fontSize)
    }

    func appFont(weight: NSFont.Weight = .regular) -> NSFont {
        fontStyle.font(ofSize: CGFloat(fontSize), weight: weight)
    }

    func resolvedContentColor(multiplier: CGFloat = 1.0) -> NSColor {
        let baseOpacity = palette.contentOpacity
        let alpha = min(max(baseOpacity * multiplier, 0), 1)
        return contentBaseColor.withAlphaComponent(alpha)
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
    static let minCornerRadius: Double = 6
    static let maxCornerRadius: Double = 24
    static let minWindowOpacity: Double = 0.3
    static let rowHorizontalInset: Double = 12
    static let textInset: Double = 8
    static let rowBackgroundInset: Double = 8
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

    // Edit these tables directly when tuning vertical text placement.
    // Keys are the discrete font size options defined above.
    private static let manualTextVerticalOffsetTable: [FontStylePreset: [Double: Double]] = [
        .system: [
            12: -1.0,
            13: -0.5,
            14: -0.5,
            15: -1.0,
            16: -2.0,
        ],
        .rounded: [
            12: -0.5,
            13: -0.5,
            14: -0.5,
            15: -1.0,
            16: -2.0,
        ],
        .serif: [
            12: -2.0,
            13: -2.0,
            14: -2.0,
            15: -2.0,
            16: -2.0,
        ],
        .monospaced: [
            12: -1.0,
            13: -0.5,
            14: -0.5,
            15: -0.5,
            16: -1.5,
        ],
    ]

    private static let displayTextVerticalOffsetTable: [FontStylePreset: [Double: Double]] = [
        .system: [
            12: 1.5,
            13: 1.5,
            14: 1.5,
            15: 2.0,
            16: 2.5,
        ],
        .rounded: [
            12: 1.5,
            13: 1.5,
            14: 1.5,
            15: 2.0,
            16: 2.5,
        ],
        .serif: [
            12: 2.5,
            13: 2.5,
            14: 2.5,
            15: 2.5,
            16: 2.5,
        ],
        .monospaced: [
            12: 1.0,
            13: 1.0,
            14: 1.5,
            15: 1.5,
            16: 1.5,
        ],
    ]

    static func maximumCornerRadius(forRowHeight rowHeight: Double) -> Double {
        let visibleRowHeight = max(0, rowHeight - (rowVerticalInset * 2.0))
        return min(maxCornerRadius, visibleRowHeight / 2.0)
    }

    static func manualTextVerticalOffset(fontStyle: FontStylePreset, fontSize: Double) -> Double {
        offset(
            for: fontStyle,
            fontSize: fontSize,
            table: manualTextVerticalOffsetTable,
            fallback: 0
        )
    }

    static func displayTextVerticalOffset(fontStyle: FontStylePreset, fontSize: Double) -> Double {
        offset(
            for: fontStyle,
            fontSize: fontSize,
            table: displayTextVerticalOffsetTable,
            fallback: 0
        )
    }

    static func nearestFontSizeOption(to value: Double) -> Double {
        fontSizeOptions.min(by: { abs($0 - value) < abs($1 - value) }) ?? defaultFontSize
    }

    private static func offset(
        for fontStyle: FontStylePreset,
        fontSize: Double,
        table: [FontStylePreset: [Double: Double]],
        fallback: Double
    ) -> Double {
        let resolvedFontSize = nearestFontSizeOption(to: fontSize)
        return table[fontStyle]?[resolvedFontSize] ?? fallback
    }
}
