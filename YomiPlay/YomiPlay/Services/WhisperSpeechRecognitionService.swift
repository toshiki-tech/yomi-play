//
//  WhisperSpeechRecognitionService.swift
//  YomiPlay
//
//  iPhone 本地 Whisper 音声認識サービス
//  WhisperKit (Argmax) を使用したオンデバイス推論
//  モデルは App Bundle に同梱されているため、ネットワーク不要
//

import Foundation
import AVFoundation

#if canImport(WhisperKit)
import WhisperKit

/// WhisperKit を使用したオンデバイス音声認識サービス
/// モデルは App Bundle (Resources/openai_whisper-tiny) から読み込む
final class WhisperSpeechRecognitionService: SpeechRecognitionServiceProtocol, @unchecked Sendable {
    
    private var whisperKit: WhisperKit?
    private var initFailed = false
    private let fallback = AppleSpeechRecognitionService()
    
    /// バンドル同梱モデルのフォルダ名
    private static let bundledModelFolder = "openai_whisper-tiny"
    
    init() {}
    
    func requestAuthorization() async -> Bool {
        return true
    }
    
    func recognize(audioURL: URL) async throws -> [RecognitionSegment] {
        if initFailed {
            print("WhisperRecognition: 前回失敗のため Apple Speech にフォールバック")
            return try await fallback.recognize(audioURL: audioURL)
        }
        
        do {
            let whisper = try await getOrInitWhisperKit()
            
            var options = DecodingOptions()
            options.language = "ja"
            options.task = .transcribe
            
            print("WhisperRecognition: 推論実行中...")
            let results = try await whisper.transcribe(audioPath: audioURL.path, decodeOptions: options)
            
            var allSegments: [RecognitionSegment] = []
            
            for result in results {
                let segments = result.segments
                for segment in segments {
                    let cleanedText = Self.cleanWhisperText(segment.text)
                    if !cleanedText.isEmpty {
                        allSegments.append(RecognitionSegment(
                            text: cleanedText,
                            startTime: Double(segment.start),
                            endTime: Double(segment.end),
                            confidence: 1.0
                        ))
                    }
                }
            }
            
            print("WhisperRecognition: 認識完了 セグメント数=\(allSegments.count)")
            return allSegments
            
        } catch {
            print("WhisperRecognition: エラー \(error.localizedDescription) → フォールバック")
            initFailed = true
            return try await fallback.recognize(audioURL: audioURL)
        }
    }
    
    private func getOrInitWhisperKit() async throws -> WhisperKit {
        if let whisper = whisperKit {
            return whisper
        }
        
        // App Bundle 内のモデルパスを取得
        let modelPath = Self.bundledModelPath()
        
        if let modelPath = modelPath {
            print("WhisperRecognition: バンドル同梱モデルを使用: \(modelPath)")
            let config = WhisperKitConfig(
                model: "openai_whisper-tiny",
                modelFolder: modelPath,
                download: false  // ダウンロードしない
            )
            let whisper = try await WhisperKit(config)
            self.whisperKit = whisper
            print("WhisperRecognition: モデル初期化完了（ローカル）✅")
            return whisper
        } else {
            // バンドルにモデルがない場合はオンラインダウンロードにフォールバック
            print("WhisperRecognition: バンドルにモデルが見つかりません、ダウンロードを試みます...")
            let whisper = try await WhisperKit()
            self.whisperKit = whisper
            print("WhisperRecognition: モデル初期化完了（ダウンロード）✅")
            return whisper
        }
    }
    
    /// App Bundle 内のモデルフォルダパスを取得する
    private static func bundledModelPath() -> String? {
        // Resources/openai_whisper-tiny フォルダを探す
        if let path = Bundle.main.path(forResource: bundledModelFolder, ofType: nil) {
            // config.json の存在でモデルフォルダの妥当性を確認
            let configPath = (path as NSString).appendingPathComponent("config.json")
            if FileManager.default.fileExists(atPath: configPath) {
                // WhisperKit は親フォルダを modelFolder として期待する
                // modelFolder/openai_whisper-tiny/ という構造
                return (path as NSString).deletingLastPathComponent
            }
        }
        return nil
    }
    
    // MARK: - Whisper テキストクリーニング
    
    static func cleanWhisperText(_ text: String) -> String {
        var cleaned = text
        
        // <|...|> タイムスタンプ・特殊トークンを除去
        if let regex = try? NSRegularExpression(pattern: "<\\|[^|]*\\|>", options: []) {
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
        }
        
        // 特殊トークンを除去
        cleaned = cleaned.replacingOccurrences(of: "[BLANK_AUDIO]", with: "")
        cleaned = cleaned.replacingOccurrences(of: "(blank_audio)", with: "")
        
        cleaned = cleaned.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        
        return cleaned
    }
}

#else

/// WhisperKit 未導入時のフォールバック
final class WhisperSpeechRecognitionService: SpeechRecognitionServiceProtocol {
    
    private let fallback = AppleSpeechRecognitionService()
    
    init() {
        print("WhisperRecognition: WhisperKit 未導入 → Apple Speech にフォールバック")
    }
    
    func requestAuthorization() async -> Bool {
        return await fallback.requestAuthorization()
    }
    
    func recognize(audioURL: URL) async throws -> [RecognitionSegment] {
        return try await fallback.recognize(audioURL: audioURL)
    }
}

#endif
