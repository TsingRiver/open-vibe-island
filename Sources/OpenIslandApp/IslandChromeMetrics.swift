import CoreGraphics

enum IslandChromeMetrics {
    static let openedShadowHorizontalInset: CGFloat = 18
    static let openedShadowBottomInset: CGFloat = 22
    static let closedShadowHorizontalInset: CGFloat = 12
    static let closedShadowBottomInset: CGFloat = 14
    static let closedHoverScale: CGFloat = 1.028
    /// Fixed status-label slot used by the detailed closed island. Keeping this
    /// width shared prevents the SwiftUI surface and AppKit hit-test rect from
    /// drifting apart.
    static let closedDetailedStatusTextWidth: CGFloat = 76
    /// Fixed session-suffix slot used by the detailed closed island. The value
    /// fits English, Simplified Chinese, and Traditional Chinese localization.
    static let closedDetailedSessionSuffixWidth: CGFloat = 76
    /// Horizontal gap between compact badges and their detailed text labels.
    static let closedDetailedTextSpacing: CGFloat = 8
}
