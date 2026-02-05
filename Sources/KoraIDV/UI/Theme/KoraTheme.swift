import SwiftUI

/// Theme configuration for UI customization
public struct KoraTheme {

    // MARK: - Colors

    /// Primary brand color
    public var primaryColor: Color

    /// Background color
    public var backgroundColor: Color

    /// Surface color (cards, overlays)
    public var surfaceColor: Color

    /// Primary text color
    public var textColor: Color

    /// Secondary text color
    public var secondaryTextColor: Color

    /// Error color
    public var errorColor: Color

    /// Success color
    public var successColor: Color

    /// Warning color
    public var warningColor: Color

    // MARK: - Typography

    /// Custom font family name (nil uses system font)
    public var fontFamily: String?

    // MARK: - Layout

    /// Corner radius for cards and buttons
    public var cornerRadius: CGFloat

    /// Default padding
    public var padding: CGFloat

    // MARK: - Initialization

    public init(
        primaryColor: Color = Color(hex: "#2563EB"),
        backgroundColor: Color = .white,
        surfaceColor: Color = Color(hex: "#F8FAFC"),
        textColor: Color = Color(hex: "#1E293B"),
        secondaryTextColor: Color = Color(hex: "#64748B"),
        errorColor: Color = Color(hex: "#DC2626"),
        successColor: Color = Color(hex: "#16A34A"),
        warningColor: Color = Color(hex: "#F59E0B"),
        fontFamily: String? = nil,
        cornerRadius: CGFloat = 12,
        padding: CGFloat = 16
    ) {
        self.primaryColor = primaryColor
        self.backgroundColor = backgroundColor
        self.surfaceColor = surfaceColor
        self.textColor = textColor
        self.secondaryTextColor = secondaryTextColor
        self.errorColor = errorColor
        self.successColor = successColor
        self.warningColor = warningColor
        self.fontFamily = fontFamily
        self.cornerRadius = cornerRadius
        self.padding = padding
    }

    // MARK: - Font Helpers

    public func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if let family = fontFamily {
            return .custom(family, size: size).weight(weight)
        }
        return .system(size: size, weight: weight)
    }

    public var titleFont: Font { font(size: 24, weight: .bold) }
    public var headlineFont: Font { font(size: 18, weight: .semibold) }
    public var bodyFont: Font { font(size: 16, weight: .regular) }
    public var captionFont: Font { font(size: 14, weight: .regular) }
    public var smallFont: Font { font(size: 12, weight: .regular) }
}

// MARK: - Color Extension

public extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Environment Key

struct KoraThemeKey: EnvironmentKey {
    static let defaultValue = KoraTheme()
}

extension EnvironmentValues {
    var koraTheme: KoraTheme {
        get { self[KoraThemeKey.self] }
        set { self[KoraThemeKey.self] = newValue }
    }
}

extension View {
    func koraTheme(_ theme: KoraTheme) -> some View {
        environment(\.koraTheme, theme)
    }
}
