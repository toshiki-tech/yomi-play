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
        dictionary[surface]
    }
}

