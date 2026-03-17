//
//  PlayerTheme.swift
//  YomiPlay
//
//  播放器界面统一配色：深色 / 浅色两套主题，主色、当前句/当前词、词性下划线等。
//  通过 Environment playerThemeScheme 解析（用户可在设置中选择跟随系统 / 浅色 / 深色）。
//

import SwiftUI

// MARK: - 环境 Key：播放器实际使用的外观（用于解析调色板）

private struct PlayerThemeSchemeKey: EnvironmentKey {
    static let defaultValue: ColorScheme = .dark
}

extension EnvironmentValues {
    /// 播放器使用的主题方案（由设置中的「主题」决定，或跟随系统）
    var playerThemeScheme: ColorScheme {
        get { self[PlayerThemeSchemeKey.self] }
        set { self[PlayerThemeSchemeKey.self] = newValue }
    }
}

// MARK: - 单套调色板（深色或浅色）

struct PlayerPalette {
    let accent: Color
    let accentHighlight: Color
    let segmentActiveBackground: Color
    let segmentActiveBorder: Color
    let segmentPressedBackground: Color
    let currentWordBackground: Color
    let currentWordBorder: Color
    let furiganaReading: Color
    let posParticle: Color
    let posVerb: Color
    let posNoun: Color
    let posOther: Color
    let englishMeaning: Color
    /// 当前句内主文字颜色（深色主题用白，浅色主题用黑，保证对比度）
    let contentForegroundActive: Color
    /// 当前句内翻译文字颜色
    let contentForegroundActiveSecondary: Color
}

// MARK: - 播放器配色（深色 / 浅色）

enum PlayerTheme {

    /// UserDefaults 存储 key：用户选择的主题 "system" | "light" | "dark"
    static let playerThemeStorageKey = "playerTheme"

    /// 根据当前使用的 ColorScheme 返回对应调色板
    static func palette(for colorScheme: ColorScheme) -> PlayerPalette {
        switch colorScheme {
        case .light: return lightPalette
        case .dark: return darkPalette
        @unknown default: return darkPalette
        }
    }

    // MARK: - 深色主题（原有效果，低亮度背景上的柔和主色）

    private static let darkPalette = PlayerPalette(
        accent: Color(hue: 0.46, saturation: 0.42, brightness: 0.62),
        accentHighlight: Color(hue: 0.46, saturation: 0.35, brightness: 0.72),
        segmentActiveBackground: Color(hue: 0.46, saturation: 0.42, brightness: 0.62).opacity(0.14),
        segmentActiveBorder: Color(hue: 0.46, saturation: 0.42, brightness: 0.62).opacity(0.38),
        segmentPressedBackground: Color(hue: 0.46, saturation: 0.42, brightness: 0.62).opacity(0.2),
        currentWordBackground: Color(hue: 0.46, saturation: 0.42, brightness: 0.62).opacity(0.18),
        currentWordBorder: Color(hue: 0.46, saturation: 0.35, brightness: 0.72).opacity(0.9),
        furiganaReading: Color(hue: 0.46, saturation: 0.32, brightness: 0.58),
        posParticle: Color(hue: 0.58, saturation: 0.25, brightness: 0.65),
        posVerb: Color(hue: 0.08, saturation: 0.45, brightness: 0.72),
        posNoun: Color(hue: 0.46, saturation: 0.30, brightness: 0.55),
        posOther: Color.primary.opacity(0.4),
        englishMeaning: Color(hue: 0.62, saturation: 0.35, brightness: 0.70),
        contentForegroundActive: .white,
        contentForegroundActiveSecondary: Color.white.opacity(0.9)
    )

    // MARK: - 浅色主题（白/浅灰背景上深色文字与清晰主色）

    private static let lightPalette = PlayerPalette(
        accent: Color(hue: 0.46, saturation: 0.52, brightness: 0.38),
        accentHighlight: Color(hue: 0.46, saturation: 0.45, brightness: 0.48),
        segmentActiveBackground: Color(hue: 0.46, saturation: 0.35, brightness: 0.50).opacity(0.12),
        segmentActiveBorder: Color(hue: 0.46, saturation: 0.45, brightness: 0.40).opacity(0.55),
        segmentPressedBackground: Color(hue: 0.46, saturation: 0.40, brightness: 0.45).opacity(0.18),
        currentWordBackground: Color(hue: 0.46, saturation: 0.40, brightness: 0.45).opacity(0.16),
        currentWordBorder: Color(hue: 0.46, saturation: 0.50, brightness: 0.40),
        furiganaReading: Color(hue: 0.46, saturation: 0.45, brightness: 0.35),
        posParticle: Color(hue: 0.58, saturation: 0.40, brightness: 0.40),
        posVerb: Color(hue: 0.08, saturation: 0.55, brightness: 0.45),
        posNoun: Color(hue: 0.46, saturation: 0.42, brightness: 0.35),
        posOther: Color.primary.opacity(0.45),
        englishMeaning: Color(hue: 0.62, saturation: 0.45, brightness: 0.45),
        contentForegroundActive: .primary,
        contentForegroundActiveSecondary: Color.primary.opacity(0.85)
    )
}
