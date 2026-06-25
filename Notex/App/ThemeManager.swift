import SwiftUI
import AppKit

// MARK: - AppTheme

enum AppTheme: String, CaseIterable, Identifiable {
    case auto = "Otomatik"
    case day = "Gündüz"
    case night = "Gece"
    case sepia = "Sepia"

    var id: String { rawValue }
    var displayName: String { rawValue }

    var iconName: String {
        switch self {
        case .auto: return "circle.lefthalf.filled"
        case .day: return "sun.max"
        case .night: return "moon"
        case .sepia: return "book"
        }
    }

    var shortLabel: String {
        switch self {
        case .auto: return "Otomatik"
        case .day: return "Gündüz"
        case .night: return "Gece"
        case .sepia: return "Sepia"
        }
    }
}

// MARK: - ViewMode (list / grid)

enum ViewMode: String, CaseIterable, Identifiable {
    case list
    case grid

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .list: return "list.bullet"
        case .grid: return "square.grid.2x2"
        }
    }

    var displayName: String {
        switch self {
        case .list: return "Liste"
        case .grid: return "Izgara"
        }
    }
}

// MARK: - Note Density

enum NoteDensity: String, CaseIterable, Identifiable {
    case comfortable
    case compact

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .comfortable: return "Rahat"
        case .compact: return "Sıkışık"
        }
    }

    var iconName: String {
        switch self {
        case .comfortable: return "rectangle.expand.vertical"
        case .compact: return "rectangle.compress.vertical"
        }
    }
}

// MARK: - Font Family

enum FontFamilyOption: String, CaseIterable, Identifiable {
    case system
    case rounded
    case serif
    case mono

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "Sistem"
        case .rounded: return "Yuvarlak"
        case .serif: return "Serif (Times)"
        case .mono: return "Mono"
        }
    }

    var iconName: String {
        switch self {
        case .system: return "textformat"
        case .rounded: return "textformat.size"
        case .serif: return "character.book.closed"
        case .mono: return "chevron.left.forwardslash.chevron.right"
        }
    }

    /// Returns a base NSFont for the editor body text.
    func nsFont(size: CGFloat) -> NSFont {
        switch self {
        case .system:
            return NSFont.systemFont(ofSize: size)
        case .rounded:
            if let descriptor = NSFontDescriptor.preferredFontDescriptor(forTextStyle: .body)
                .withDesign(.rounded) {
                return NSFont(descriptor: descriptor, size: size) ?? NSFont.systemFont(ofSize: size)
            }
            return NSFont.systemFont(ofSize: size)
        case .serif:
            return NSFont(name: "Times New Roman", size: size) ?? NSFont.systemFont(ofSize: size)
        case .mono:
            if let descriptor = NSFontDescriptor.preferredFontDescriptor(forTextStyle: .body)
                .withDesign(.monospaced) {
                return NSFont(descriptor: descriptor, size: size) ?? NSFont.systemFont(ofSize: size)
            }
            return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        }
    }

    /// SwiftUI Font for preview / UI text.
    func swiftUIFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch self {
        case .system: return .system(size: size, weight: weight)
        case .rounded: return .system(size: size, weight: weight, design: .rounded)
        case .serif: return .system(size: size, weight: weight, design: .serif)
        case .mono: return .system(size: size, weight: weight, design: .monospaced)
        }
    }
}

// MARK: - Accent Color

enum AccentColorOption: String, CaseIterable, Identifiable {
    case blue, purple, pink, red, orange, yellow, green, teal, indigo, mint

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .blue: return Color(red: 0.21, green: 0.48, blue: 0.91)
        case .purple: return Color(red: 0.58, green: 0.35, blue: 0.82)
        case .pink: return Color(red: 0.95, green: 0.38, blue: 0.62)
        case .red: return Color(red: 0.90, green: 0.27, blue: 0.27)
        case .orange: return Color(red: 0.95, green: 0.55, blue: 0.20)
        case .yellow: return Color(red: 0.92, green: 0.76, blue: 0.22)
        case .green: return Color(red: 0.30, green: 0.74, blue: 0.44)
        case .teal: return Color(red: 0.20, green: 0.70, blue: 0.68)
        case .indigo: return Color(red: 0.31, green: 0.33, blue: 0.74)
        case .mint: return Color(red: 0.18, green: 0.74, blue: 0.60)
        }
    }

    var displayName: String {
        switch self {
        case .blue: return "Mavi"
        case .purple: return "Mor"
        case .pink: return "Pembe"
        case .red: return "Kırmızı"
        case .orange: return "Turuncu"
        case .yellow: return "Sarı"
        case .green: return "Yeşil"
        case .teal: return "Turkuaz"
        case .indigo: return "Çivit"
        case .mint: return "Nane"
        }
    }
}

// MARK: - ThemeManager

final class ThemeManager: ObservableObject {
    @Published var theme: AppTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: "theme")
            applyTheme()
        }
    }

    @AppStorage("accentColor") var accentColorRaw: String = AccentColorOption.green.rawValue
    @AppStorage("fontSize") var fontSize: Double = 15
    @AppStorage("lineSpacing") var lineSpacing: Double = 1.5
    @AppStorage("fontFamily") var fontFamilyRaw: String = FontFamilyOption.system.rawValue
    @AppStorage("noteDensity") var noteDensityRaw: String = NoteDensity.comfortable.rawValue
    @AppStorage("defaultViewMode") var defaultViewModeRaw: String = ViewMode.list.rawValue

    @Published var backgroundColor: Color = .white
    @Published var textColor: Color = .primary
    @Published var editorBackground: Color = .white
    @Published var cardBackground: Color = .white
    @Published var sidebarBackground: Color = Color(NSColor.windowBackgroundColor)
    @Published var secondaryText: Color = Color.secondary.opacity(0.6)

    /// Live view-mode for the note list (starts from stored default, user-togglable).
    @Published var viewMode: ViewMode

    /// Token for the system-appearance observer (used by .auto mode).
    private var appearanceObserver: NSObjectProtocol?

    init() {
        let raw = UserDefaults.standard.string(forKey: "theme") ?? AppTheme.day.rawValue
        self.theme = AppTheme(rawValue: raw) ?? .day

        let vraw = UserDefaults.standard.string(forKey: "defaultViewMode") ?? ViewMode.list.rawValue
        self.viewMode = ViewMode(rawValue: vraw) ?? .list

        applyTheme()

        // React to system appearance changes when in .auto mode.
        appearanceObserver = DistributedNotificationCenter.default.addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.theme == .auto else { return }
            self.applyTheme()
        }
    }

    deinit {
        if let observer = appearanceObserver {
            DistributedNotificationCenter.default.removeObserver(observer)
        }
    }

    /// True when the active theme resolves to a dark appearance.
    /// `.auto` follows the system; `.night` is always dark; `.day`/`.sepia` are light.
    var isDarkMode: Bool {
        switch theme {
        case .auto:
            let best = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .vibrantDark, .aqua, .vibrantLight])
            return best == .darkAqua || best == .vibrantDark
        case .night: return true
        case .day, .sepia: return false
        }
    }

    var colorScheme: ColorScheme? {
        switch theme {
        case .auto: return nil   // follow system
        case .day: return .light
        case .night: return .dark
        case .sepia: return .light
        }
    }

    var accentColor: Color {
        AccentColorOption(rawValue: accentColorRaw)?.color ?? AccentColorOption.green.color
    }

    var accentColorOption: AccentColorOption {
        AccentColorOption(rawValue: accentColorRaw) ?? .green
    }

    var fontFamily: FontFamilyOption {
        FontFamilyOption(rawValue: fontFamilyRaw) ?? .system
    }

    var noteDensity: NoteDensity {
        NoteDensity(rawValue: noteDensityRaw) ?? .comfortable
    }

    var defaultViewMode: ViewMode {
        ViewMode(rawValue: defaultViewModeRaw) ?? .list
    }

    func setAccentColor(_ option: AccentColorOption) {
        accentColorRaw = option.rawValue
    }

    func setFontFamily(_ option: FontFamilyOption) {
        fontFamilyRaw = option.rawValue
    }

    func setNoteDensity(_ option: NoteDensity) {
        noteDensityRaw = option.rawValue
    }

    func setDefaultViewMode(_ option: ViewMode) {
        defaultViewModeRaw = option.rawValue
        viewMode = option
    }

    func cycleTheme() {
        switch theme {
        case .auto: theme = .day
        case .day: theme = .night
        case .night: theme = .sepia
        case .sepia: theme = .auto
        }
    }

    private func applyTheme() {
        switch theme {
        case .auto:
            if isDarkMode { applyNightColors() } else { applyDayColors() }
        case .day:
            applyDayColors()
        case .night:
            applyNightColors()
        case .sepia:
            // Warm cream: #F5E8C9
            backgroundColor = Color(red: 245.0/255.0, green: 232.0/255.0, blue: 201.0/255.0)
            editorBackground = Color(red: 248.0/255.0, green: 237.0/255.0, blue: 209.0/255.0)
            cardBackground = Color(red: 251.0/255.0, green: 243.0/255.0, blue: 221.0/255.0)
            sidebarBackground = Color(red: 237.0/255.0, green: 224.0/255.0, blue: 192.0/255.0)
            textColor = Color(red: 0.27, green: 0.22, blue: 0.13)
            secondaryText = Color(red: 0.40, green: 0.33, blue: 0.20)
        }
    }

    private func applyDayColors() {
        backgroundColor = Color(NSColor.windowBackgroundColor)
        editorBackground = Color.white
        cardBackground = Color.white
        sidebarBackground = Color(NSColor.windowBackgroundColor)
        textColor = .primary
        secondaryText = Color.secondary.opacity(0.6)
    }

    private func applyNightColors() {
        // True dark: #1C1C1E base, slightly lighter surfaces
        backgroundColor = Color(red: 28.0/255.0, green: 28.0/255.0, blue: 30.0/255.0)
        editorBackground = Color(red: 28.0/255.0, green: 28.0/255.0, blue: 30.0/255.0)
        cardBackground = Color(red: 44.0/255.0, green: 44.0/255.0, blue: 46.0/255.0)
        sidebarBackground = Color(red: 24.0/255.0, green: 24.0/255.0, blue: 26.0/255.0)
        textColor = Color.white
        secondaryText = Color.white.opacity(0.55)
    }
}
