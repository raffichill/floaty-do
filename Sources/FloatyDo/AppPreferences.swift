import Foundation

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

public struct AppPreferences: Codable, Equatable {
    public var rowHeight: Double
    public var panelWidth: Double
    public var hoverHighlightsEnabled: Bool
    public var animationPreset: AnimationPreset
    public var snapPadding: Double

    public static let `default` = AppPreferences(
        rowHeight: 36,
        panelWidth: 400,
        hoverHighlightsEnabled: true,
        animationPreset: .balanced,
        snapPadding: 40
    )

    var motion: MotionProfile { animationPreset.motion }
}

enum LayoutMetrics {
    static let minPanelWidth: Double = 320
    static let maxPanelWidth: Double = 520
    static let minRowHeight: Double = 32
    static let maxRowHeight: Double = 48
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
