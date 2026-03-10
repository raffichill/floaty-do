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
        red: 0.22745098,
        green: 0.22745098,
        blue: 0.2627451,
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
        snapPadding: 40,
        themeColor: .default,
        fontStyle: .system,
        fontSize: 13,
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
    var activeFillColor: NSColor {
        themeColor.nsColor
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
    static let minFontSize: Double = 12
    static let maxFontSize: Double = 18
    static let minCornerRadius: Double = 6
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
}
