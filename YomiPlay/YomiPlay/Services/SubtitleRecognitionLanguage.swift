//
//  SubtitleRecognitionLanguage.swift
//  YomiPlay
//
//  字幕「原文语言」与假名/翻译共用的规范化逻辑（不依赖 WhisperKit 类型，供 #if 分支共用）。
//

import Foundation

enum SubtitleRecognitionLanguage {

    /// 用户选择「整段为非日语识别」时，Whisper 会跳过按句区分日语
    static func forcesNonJapaneseSegments(lang: String) -> Bool {
        if lang == "ja" || lang == "auto" { return false }
        return true
    }

    /// 将 Whisper `TranscriptionResult.language`（多为 ISO 639-1 或英文语言名）规范为字幕存储用简码（ja/en/zh 等）
    static func normalizedStoredLanguageFromWhisperOutput(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        let lower = t.lowercased()

        let primary = lower.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? lower
        if primary.count == 2 || primary.count == 3 {
            switch primary {
            case "ja": return "ja"
            case "en": return "en"
            case "zh": return "zh"
            case "ko": return "ko"
            case "yue": return "zh"
            default: return primary
            }
        }

        let nameMap: [String: String] = [
            "japanese": "ja",
            "english": "en",
            "chinese": "zh",
            "mandarin": "zh",
            "cantonese": "zh",
            "korean": "ko",
            "french": "fr",
            "german": "de",
            "spanish": "es",
        ]
        if let code = nameMap[lower] { return code }

        for (name, code) in nameMap where lower.contains(name) {
            return code
        }
        return nil
    }

    /// 写入 `TranscriptSegment.originalTextLanguageCode`（与识别设置、Whisper 语言标签、分句文本一致）
    static func storedOriginalTextLanguageCode(
        recognitionUserSetting: String,
        lineLooksJapanese: Bool,
        whisperDetectedLanguageCode: String?
    ) -> String? {
        let lang = recognitionUserSetting
        if forcesNonJapaneseSegments(lang: lang) {
            return lang == "auto" ? nil : lang
        }

        if let w = whisperDetectedLanguageCode,
           let fromWhisper = normalizedStoredLanguageFromWhisperOutput(w) {
            if lang == "auto" || lang == "ja" {
                return fromWhisper
            }
        }

        switch lang {
        case "auto": return lineLooksJapanese ? "ja" : "en"
        case "ja": return lineLooksJapanese ? "ja" : "en"
        case "en", "zh": return lang
        default: return lang == "auto" ? nil : lang
        }
    }

    /// 是否对该句生成假名：在「日语/自动」模式下优先用 Whisper 语言标签区分日语与中文等；无标签时回退到字符启发式
    static func segmentAppearsJapaneseForFurigana(
        userRecognitionLanguage: String,
        text: String,
        whisperLanguageCode: String?
    ) -> Bool {
        if forcesNonJapaneseSegments(lang: userRecognitionLanguage) {
            return false
        }
        if let w = whisperLanguageCode,
           let iso = normalizedStoredLanguageFromWhisperOutput(w) {
            switch iso {
            case "ja": return true
            case "zh", "en", "ko", "fr", "de", "es": return false
            default: return false
            }
        }
        return isLikelyJapaneseByScript(text)
    }

    /// 平假名/片假名/CJK 汉字 → 视为「日语侧」显示路径（与旧逻辑一致；无法区分中日文时依赖 Whisper 标签）
    static func isLikelyJapaneseByScript(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return true }
        for ch in t.unicodeScalars {
            switch ch.value {
            case 0x3040..<0x30A0: return true
            case 0x30A0..<0x3100: return true
            case 0x4E00..<0xA000: return true
            default: break
            }
        }
        return false
    }

    /// 根据各句语言推断「整份是否为非日语材料」：自动/日语模式下若多数句非 ja，则默认关假名等
    static func inferNonJapaneseDocumentFlag(
        recognitionSetting: String,
        segments: [TranscriptSegment],
        forcedNonJapanese: Bool
    ) -> Bool? {
        if forcedNonJapanese { return true }
        guard recognitionSetting == "auto" || recognitionSetting == "ja" else { return nil }
        let codes = segments.compactMap { $0.originalTextLanguageCode }
        guard codes.count >= 2 else { return nil }
        let nonJa = codes.filter { $0 != "ja" }.count
        return Double(nonJa) / Double(codes.count) >= 0.55 ? true : nil
    }
}
