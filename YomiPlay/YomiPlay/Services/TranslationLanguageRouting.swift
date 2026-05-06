//
//  TranslationLanguageRouting.swift
//  YomiPlay
//
//  系统 Translation 的源语言解析、与目标语相同时跳过、BCP-47 规范化
//

import Foundation

enum TranslationLanguageRouting {

    /// 单条字幕 → TranslationSession 用的源语言标识符
    static func sourceLanguageIdentifierForTranslation(
        originalTextLanguageCode: String?,
        documentNonJapaneseRecognitionSource: Bool?
    ) -> String {
        if let s = originalTextLanguageCode?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            return normalizeCodeForAppleTranslationSession(s)
        }
        if documentNonJapaneseRecognitionSource == true {
            let g = UserDefaults.standard.string(forKey: WhisperSpeechRecognitionService.sourceLanguageDefaultsKey) ?? "en"
            let resolved = (g == "auto") ? "en" : g
            return normalizeCodeForAppleTranslationSession(resolved)
        }
        return "ja"
    }

    static func normalizeCodeForAppleTranslationSession(_ code: String) -> String {
        let t = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "ja" }
        let lower = t.lowercased()
        switch lower {
        case "zh", "zh-cn", "zh-hans", "zh_sg", "zh-sg": return "zh-Hans"
        case "zh-tw", "zh-hk", "zh-mo", "zh-hant": return "zh-Hant"
        case "yue": return "zh-Hant"
        default:
            return TranslationTargetLanguageOptions.normalizedCode(t)
        }
    }

    /// 源语与目标语是否视为同一种（无需调用系统翻译）
    static func shouldSkipTranslationBecauseSameLanguage(sourceIdentifier: String, targetLanguageCode: String) -> Bool {
        let s = normalizeCodeForAppleTranslationSession(sourceIdentifier)
        let t = normalizeCodeForAppleTranslationSession(targetLanguageCode)
        return s == t
    }
}
