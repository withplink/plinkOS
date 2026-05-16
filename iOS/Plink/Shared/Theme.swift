import SwiftUI

struct Palette {
    let bg: Color
    let surf: Color
    let ink: Color
    let sub: Color
    let line: Color
    let accent: Color
    let accentInk: Color
    let chip: Color
}

extension Palette {
    static let rose = Palette(
        bg: Color(red: 0.969, green: 0.941, blue: 0.929),
        surf: .white,
        ink: Color(red: 0.12, green: 0.10, blue: 0.09),
        sub: Color(red: 0.44, green: 0.40, blue: 0.38),
        line: Color(red: 0.88, green: 0.84, blue: 0.82),
        accent: Color(red: 0.84, green: 0.35, blue: 0.36),
        accentInk: .white,
        chip: Color(red: 0.94, green: 0.91, blue: 0.90)
    )

    static let ash = Palette(
        bg: Color(red: 0.95, green: 0.96, blue: 0.97),
        surf: .white,
        ink: Color(red: 0.10, green: 0.11, blue: 0.14),
        sub: Color(red: 0.40, green: 0.42, blue: 0.48),
        line: Color(red: 0.85, green: 0.87, blue: 0.91),
        accent: Color(red: 0.30, green: 0.42, blue: 0.65),
        accentInk: .white,
        chip: Color(red: 0.91, green: 0.92, blue: 0.95)
    )

    static let sun = Palette(
        bg: Color(red: 0.97, green: 0.95, blue: 0.91),
        surf: .white,
        ink: Color(red: 0.14, green: 0.11, blue: 0.06),
        sub: Color(red: 0.42, green: 0.38, blue: 0.28),
        line: Color(red: 0.88, green: 0.84, blue: 0.76),
        accent: Color(red: 0.88, green: 0.68, blue: 0.18),
        accentInk: Color(red: 0.14, green: 0.10, blue: 0.04),
        chip: Color(red: 0.94, green: 0.91, blue: 0.85)
    )

    static let inkDark = Palette(
        bg: Color(red: 0.10, green: 0.09, blue: 0.08),
        surf: Color(red: 0.14, green: 0.12, blue: 0.11),
        ink: Color(red: 0.95, green: 0.92, blue: 0.88),
        sub: Color(red: 0.58, green: 0.54, blue: 0.50),
        line: Color(red: 0.22, green: 0.19, blue: 0.17),
        accent: Color(red: 0.84, green: 0.35, blue: 0.36),
        accentInk: Color(red: 0.10, green: 0.08, blue: 0.06),
        chip: Color(red: 0.18, green: 0.15, blue: 0.14)
    )
}

enum PaletteChoice: String, CaseIterable {
    case rose, ash, sun, ink

    var palette: Palette {
        switch self {
        case .rose: return .rose
        case .ash: return .ash
        case .sun: return .sun
        case .ink: return .inkDark
        }
    }

    var displayName: String { rawValue.capitalized }

    var swatch: Color { palette.accent }

    var isDark: Bool { self == .ink }
}

struct PaletteKey: EnvironmentKey {
    static let defaultValue: Palette = .rose
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}
