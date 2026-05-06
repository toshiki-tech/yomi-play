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
    private var bundledDictionary: [String: String] = [:]
    private static let customDictionaryDefaultsKey = "katakanaEnglishCustomDictionary"
    
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
            bundledDictionary = decoded
            dictionary = decoded
            mergeCustomDictionary()
            print("KatakanaDictionaryService: loaded \(decoded.count) bundled entries")
        } catch {
            print("KatakanaDictionaryService: failed to load dictionary - \(error)")
        }
    }

    private func mergeCustomDictionary() {
        let stored = UserDefaults.standard.dictionary(forKey: Self.customDictionaryDefaultsKey) as? [String: String] ?? [:]
        for (key, value) in stored {
            let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedKey.isEmpty, !normalizedValue.isEmpty else { continue }
            dictionary[normalizedKey] = normalizedValue
        }
    }
    
    /// 片仮名語 surface に対応する英語原綴りを返す
    func lookup(_ surface: String) -> String? {
        guard let raw = dictionary[surface] else { return nil }
        return Self.simplifiedEnglish(from: raw)
    }

    /// 更新（或新增）片假名词条映射，并持久化到用户词库
    func upsert(surface: String, englishMeaning: String) {
        let normalizedSurface = surface.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedMeaning = englishMeaning.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSurface.isEmpty, !normalizedMeaning.isEmpty else { return }
        dictionary[normalizedSurface] = normalizedMeaning

        var stored = UserDefaults.standard.dictionary(forKey: Self.customDictionaryDefaultsKey) as? [String: String] ?? [:]
        stored[normalizedSurface] = normalizedMeaning
        UserDefaults.standard.set(stored, forKey: Self.customDictionaryDefaultsKey)
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

