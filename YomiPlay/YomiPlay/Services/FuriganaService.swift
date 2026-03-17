//
//  FuriganaService.swift
//  YomiPlay
//
//  振り仮名 + ローマ字生成サービス
//  方案二：NLTokenizer 分词（改善复合词如報告書）+ CFStringTokenizer 取读音
//

import Foundation
import NaturalLanguage

// MARK: - プロトコル定義

/// 振り仮名生成サービスのプロトコル
protocol FuriganaServiceProtocol: Sendable {
    /// テキストから振り仮名トークンを生成する
    func generateFurigana(for text: String) async -> [FuriganaToken]
}

// MARK: - CFStringTokenizer実装

/// CFStringTokenizerを使用した振り仮名 + ローマ字生成サービス
final class CFStringTokenizerFuriganaService: FuriganaServiceProtocol {
    
    func generateFurigana(for text: String) async -> [FuriganaToken] {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let tokens = self.tokenize(text: text)
                continuation.resume(returning: tokens)
            }
        }
    }
    
    /// 方案二：NLTokenizer 分词（复合词如報告書成词）+ CFStringTokenizer 仅用于取读音
    private func tokenize(text: String) -> [FuriganaToken] {
        guard !text.isEmpty else { return [] }
        
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        tokenizer.setLanguage(NLLanguage.japanese)
        let nlRanges = tokenizer.tokens(for: text.startIndex..<text.endIndex)
        
        var tokens: [FuriganaToken] = []
        var lastIndex = text.startIndex
        
        for range in nlRanges {
            // 区间之间的空白/标点等作为独立 token
            if lastIndex < range.lowerBound {
                appendSkippedToken(text: text, from: lastIndex, to: range.lowerBound, into: &tokens)
            }
            let surface = String(text[range])
            let (reading, romaji) = readingAndRomaji(for: surface)
            let hasKanji = surface.unicodeScalars.contains { scalar in
                (0x4E00...0x9FFF).contains(scalar.value) ||
                (0x3400...0x4DBF).contains(scalar.value)
            }
            let isKatakana = Self.isKatakanaWord(surface)
            let english = isKatakana ? KatakanaDictionaryService.shared.lookup(surface) : nil
            tokens.append(FuriganaToken(
                surface: surface,
                reading: reading,
                romaji: romaji,
                isKanji: hasKanji,
                isKatakana: isKatakana,
                englishMeaning: english,
                partOfSpeech: Self.partOfSpeech(surface: surface, reading: reading)
            ))
            lastIndex = range.upperBound
        }
        
        if lastIndex < text.endIndex {
            appendSkippedToken(text: text, from: lastIndex, to: text.endIndex, into: &tokens)
        }
        
        return tokens
    }
    
    /// 对给定字符串用 CFStringTokenizer 取振假名与罗马字（多子词时拼接）
    private func readingAndRomaji(for string: String) -> (reading: String, romaji: String) {
        guard !string.isEmpty else { return ("", "") }
        let nsStr = string as NSString
        let range = CFRange(location: 0, length: nsStr.length)
        let locale = Locale(identifier: "ja") as CFLocale
        let tokenizer = CFStringTokenizerCreate(
            kCFAllocatorDefault,
            string as CFString,
            range,
            kCFStringTokenizerUnitWordBoundary,
            locale
        )
        var readingParts: [String] = []
        var romajiParts: [String] = []
        var tokenType = CFStringTokenizerAdvanceToNextToken(tokenizer)
        
        while tokenType != [] {
            let tokenRange = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            let startIdx = string.index(string.startIndex, offsetBy: tokenRange.location)
            let endIdx = string.index(startIdx, offsetBy: tokenRange.length)
            let sub = String(string[startIdx..<endIdx])
            
            if let latinRef = CFStringTokenizerCopyCurrentTokenAttribute(
                tokenizer,
                kCFStringTokenizerAttributeLatinTranscription
            ) {
                let latin = latinRef as! CFString
                let romajiString = (latin as String).lowercased()
                let mutableLatin = NSMutableString(string: latin as String)
                CFStringTransform(mutableLatin, nil, kCFStringTransformLatinHiragana, false)
                readingParts.append(mutableLatin as String)
                romajiParts.append(romajiString)
            } else {
                let romaji = Self.hiraganaToRomaji(sub)
                readingParts.append(sub)
                romajiParts.append(romaji)
            }
            tokenType = CFStringTokenizerAdvanceToNextToken(tokenizer)
        }
        
        if readingParts.isEmpty {
            let romaji = Self.hiraganaToRomaji(string)
            return (string, romaji)
        }
        return (readingParts.joined(), romajiParts.joined())
    }
    
    /// 将分词区间之间的内容（标点、空格等）追加为 token
    private func appendSkippedToken(text: String, from start: String.Index, to end: String.Index, into tokens: inout [FuriganaToken]) {
        let skippedText = String(text[start..<end])
        guard !skippedText.isEmpty else { return }
        let romaji = Self.hiraganaToRomaji(skippedText)
        let isKatakana = Self.isKatakanaWord(skippedText)
        let english = isKatakana ? KatakanaDictionaryService.shared.lookup(skippedText) : nil
        tokens.append(FuriganaToken(
            surface: skippedText,
            reading: skippedText,
            romaji: romaji,
            isKanji: false,
            isKatakana: isKatakana,
            englishMeaning: english,
            partOfSpeech: Self.partOfSpeech(surface: skippedText, reading: skippedText)
        ))
    }
    
    // MARK: - 詞性（品詞）启发式
    
    /// 根据 surface / reading 做简单词性分类，用于按词性下划线
    private static func partOfSpeech(surface: String, reading: String) -> PartOfSpeech {
        let r = reading.trimmingCharacters(in: .whitespacesAndNewlines)
        let s = surface.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !r.isEmpty || !s.isEmpty else { return .other }
        let hira = r.isEmpty ? s : r
        // 助詞：常见助词（含促音・长音后的形态）
        let particles: Set<String> = [
            "は", "が", "を", "に", "で", "と", "の", "へ", "も", "か", "や", "など", "から", "まで", "より",
            "ので", "のに", "ば", "て", "で", "が", "は", "を", "ね", "よ", "な", "さ", "ぞ", "とも", "しか",
            "だけ", "ほど", "くらい", "など", "とか", "やら", "なり", "こそ", "でも", "には", "では",
            "へは", "をも", "にも", "では", "とは", "からは", "までは"
        ]
        if particles.contains(hira) || particles.contains(s) { return .particle }
        // 動詞：読みが う/く/す/つ/ぬ/ぶ/む/る 等で終わる（一段・五段活用）
        let verbEndings = ["う", "く", "す", "つ", "ぬ", "ぶ", "む", "る", "く", "ぐ", "す", "つ", "ぬ", "ぶ", "む", "う", "いる", "える", "できる", "する", "くる", "ある"]
        let lastOne = hira.count >= 1 ? String(hira.suffix(1)) : ""
        let lastTwo = hira.count >= 2 ? String(hira.suffix(2)) : ""
        if verbEndings.contains(lastOne) || verbEndings.contains(lastTwo) { return .verb }
        // 名词：默认（漢語・和語名詞等）
        if s.unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) }) { return .noun }
        if !hira.isEmpty && hira.count >= 2 { return .noun }
        return .other
    }
    
    // MARK: - ひらがな / カタカナ判定・変換
    
    /// 文字列が片仮名のみ（長音符「ー」や中点「・」を含む）の場合に true を返す
    static func isKatakanaWord(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        var hasKatakana = false
        for scalar in text.unicodeScalars {
            let v = scalar.value
            // カタカナブロック
            if (0x30A0...0x30FF).contains(v) {
                hasKatakana = true
                continue
            }
            // 長音符・中点などを許可
            if v == 0x30FC || v == 0x30FB {
                continue
            }
            // 上記以外が含まれていれば片仮名語とはみなさない
            return false
        }
        return hasKatakana
    }
    
    // MARK: - ひらがな → ローマ字変換
    
    /// CFStringTransform でひらがな/カタカナをローマ字に変換する
    static func hiraganaToRomaji(_ text: String) -> String {
        let mutable = NSMutableString(string: text)
        // まずひらがなをラテン文字に変換
        CFStringTransform(mutable, nil, kCFStringTransformLatinHiragana, true) // reverse
        // カタカナもカバー
        CFStringTransform(mutable, nil, kCFStringTransformLatinKatakana, true) // reverse
        // アクセント記号を除去
        CFStringTransform(mutable, nil, kCFStringTransformStripCombiningMarks, false)
        return (mutable as String).lowercased()
    }
}
