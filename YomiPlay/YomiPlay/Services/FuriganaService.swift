//
//  FuriganaService.swift
//  YomiPlay
//
//  振り仮名 + ローマ字生成サービス
//  CFStringTokenizerを使用して漢字の読みとローマ字を取得する
//

import Foundation

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
    
    /// テキストをトークナイズし、漢字には読みとローマ字を付ける
    private func tokenize(text: String) -> [FuriganaToken] {
        guard !text.isEmpty else { return [] }
        
        var tokens: [FuriganaToken] = []
        let nsText = text as NSString
        let range = CFRangeMake(0, nsText.length)
        
        let locale = Locale(identifier: "ja") as CFLocale
        let tokenizer = CFStringTokenizerCreate(
            kCFAllocatorDefault,
            text as CFString,
            range,
            kCFStringTokenizerUnitWordBoundary,
            locale
        )
        
        var tokenType = CFStringTokenizerAdvanceToNextToken(tokenizer)
        var lastIndex = text.startIndex
        
        while tokenType != [] {
            let tokenRange = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            
            let startIdx = text.index(text.startIndex, offsetBy: tokenRange.location)
            let endIdx = text.index(startIdx, offsetBy: tokenRange.length)
            
            // トークン前の未処理テキスト
            if lastIndex < startIdx {
                let skippedText = String(text[lastIndex..<startIdx])
                let skippedRomaji = Self.hiraganaToRomaji(skippedText)
                tokens.append(FuriganaToken(
                    surface: skippedText,
                    reading: skippedText,
                    romaji: skippedRomaji,
                    isKanji: false
                ))
            }
            
            let surface = String(text[startIdx..<endIdx])
            
            if let latinRef = CFStringTokenizerCopyCurrentTokenAttribute(
                tokenizer,
                kCFStringTokenizerAttributeLatinTranscription
            ) {
                let latin = latinRef as! CFString
                let romajiString = (latin as String).lowercased()
                
                // ローマ字をひらがなに変換
                let mutableLatin = NSMutableString(string: latin as String)
                CFStringTransform(mutableLatin, nil, kCFStringTransformLatinHiragana, false)
                let reading = mutableLatin as String
                
                let hasKanji = surface.unicodeScalars.contains { scalar in
                    (0x4E00...0x9FFF).contains(scalar.value) ||
                    (0x3400...0x4DBF).contains(scalar.value)
                }
                
                tokens.append(FuriganaToken(
                    surface: surface,
                    reading: reading,
                    romaji: romajiString,
                    isKanji: hasKanji
                ))
            } else {
                let romaji = Self.hiraganaToRomaji(surface)
                tokens.append(FuriganaToken(
                    surface: surface,
                    reading: surface,
                    romaji: romaji,
                    isKanji: false
                ))
            }
            
            lastIndex = endIdx
            tokenType = CFStringTokenizerAdvanceToNextToken(tokenizer)
        }
        
        if lastIndex < text.endIndex {
            let remaining = String(text[lastIndex..<text.endIndex])
            let romaji = Self.hiraganaToRomaji(remaining)
            tokens.append(FuriganaToken(
                surface: remaining,
                reading: remaining,
                romaji: romaji,
                isKanji: false
            ))
        }
        
        return tokens
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
