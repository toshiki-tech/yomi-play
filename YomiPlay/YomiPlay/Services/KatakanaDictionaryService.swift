//
//  KatakanaDictionaryService.swift
//  YomiPlay
//
//  片仮名外来語 -> 英語原綴り の簡易辞書
//

import Foundation

/// バンドル内の JSON から片仮名外来語辞書を読み込むサービス
final class KatakanaDictionaryService {
    
    static let shared = KatakanaDictionaryService()
    
    private var dictionary: [String: String] = [:]
    
    private init() {
        loadDictionary()
    }
    
    private func loadDictionary() {
        guard let url = Bundle.main.url(forResource: "katakana_english", withExtension: "json") else {
            print("KatakanaDictionaryService: katakana_english.json not found in bundle")
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([String: String].self, from: data)
            dictionary = decoded
            print("KatakanaDictionaryService: loaded \(decoded.count) entries")
        } catch {
            print("KatakanaDictionaryService: failed to load dictionary - \(error)")
        }
    }
    
    /// 片仮名語 surface に対応する英語原綴りを返す
    func lookup(_ surface: String) -> String? {
        guard let raw = dictionary[surface] else { return nil }
        return Self.simplifiedEnglish(from: raw)
    }
    
    /// 辞書内の英語訳から、UI に表示するための短いラベルを生成する
    private static func simplifiedEnglish(from text: String) -> String {
        var result = text
        
        // カンマ以降や括弧内は説明が長くなりがちなので削る
        if let parenIndex = result.firstIndex(of: "(") {
            result = String(result[..<parenIndex])
        }
        if let commaIndex = result.firstIndex(of: ",") {
            result = String(result[..<commaIndex])
        }
        
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 依然として長い場合は、先頭の数単語だけを残す
        let words = result.split(whereSeparator: { $0.isWhitespace })
        if words.count > 3 {
            result = words.prefix(3).joined(separator: " ")
        }
        
        return result
    }
}

