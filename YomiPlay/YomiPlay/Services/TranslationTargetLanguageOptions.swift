//
//  TranslationTargetLanguageOptions.swift
//  YomiPlay
//
//  翻译目标语言：可选范围（BCP-47）与「跟随系统首选语言」的默认解析
//

import Foundation

enum TranslationTargetLanguageOptions {

    /// 常见翻译目标，供 Picker 与 TranslationSession；可按需再扩容
    static let allCodes: [String] = [
        "zh-Hans", "zh-Hant", "ja", "en", "ko",
        "fr", "de", "es", "pt-BR", "pt-PT", "it", "ru",
        "ar", "hi", "th", "vi", "id", "ms", "tl", "tr", "pl", "uk", "nl",
        "sv", "da", "fi", "nb", "cs", "sk", "hu", "ro", "bg", "hr", "sl",
        "el", "he", "ca", "bn", "ta", "mr",
    ]

    private static let codeSet: Set<String> = Set(allCodes)

    /// 根据系统首选语言取默认翻译目标（首次安装或未保存过时使用）
    static func defaultTargetCode() -> String {
        for id in Locale.preferredLanguages where !id.isEmpty {
            let lang = Locale.Language(identifier: id)
            if lang.languageCode?.identifier == "zh" {
                let r = lang.region?.identifier
                if r == "TW" || r == "HK" || r == "MO" { return "zh-Hant" }
                return "zh-Hans"
            }
            if codeSet.contains(id) { return id }
            if let base = lang.languageCode?.identifier, codeSet.contains(base) { return base }
            if let base = lang.languageCode?.identifier,
               let match = allCodes.first(where: {
                   Locale.Language(identifier: $0).languageCode?.identifier == base
               }) {
                return match
            }
        }
        return "en"
    }

    /// 将 UserDefaults 或历史值规范到列表内；未知则回退默认
    static func normalizedCode(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return defaultTargetCode() }
        if codeSet.contains(t) { return t }

        let aliases: [String: String] = [
            "zh": "zh-Hans",
            "zh-CN": "zh-Hans",
            "zh-TW": "zh-Hant",
            "zh-HK": "zh-Hant",
            "in": "id",
            "iw": "he",
            "no": "nb",
            "pt": "pt-BR",
        ]
        if let m = aliases[t] { return normalizedCode(m) }

        let lower = t.lowercased()
        if codeSet.contains(lower) { return lower }

        if let base = t.split(separator: "-").first.map(String.init), codeSet.contains(base) {
            return base
        }
        if let match = allCodes.first(where: { $0.lowercased() == lower }) { return match }
        if let base = t.split(separator: "-").first.map(String.init),
           let match = allCodes.first(where: { $0.hasPrefix(base + "-") || $0 == base }) {
            return match
        }
        return defaultTargetCode()
    }

    static func resolvedStoredOrDefault() -> String {
        if let s = UserDefaults.standard.string(forKey: "targetLanguageCode"), !s.isEmpty {
            return normalizedCode(s)
        }
        return defaultTargetCode()
    }

    static func displayName(code: String, locale: Locale) -> String {
        let id = normalizedCode(code)
        let loc = Locale(identifier: locale.identifier)
        if let s = loc.localizedString(forIdentifier: id), !s.isEmpty { return s }
        if let head = id.split(separator: "-").first,
           let s = loc.localizedString(forLanguageCode: String(head)), !s.isEmpty { return s }
        return id
    }
}
