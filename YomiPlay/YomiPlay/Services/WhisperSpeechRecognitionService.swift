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
    /// 現在キャッシュ中のモデル名。設定が変わったら破棄して再ロードする
    private var loadedModelFolder: String?
    
    /// UserDefaults に保存するモデル選択キー
    static let modelVariantDefaultsKey = "whisperModelVariant"
    /// 识别时偏好日语（true=主要日语内容不易被误识为英文；false=自动检测，便于节目中夹杂多语时各语言正确输出）
    static let preferJapaneseDefaultsKey = "whisperPreferJapanese"
    
    /// バンドル同梱モデルのフォルダ名（UserDefaults の設定に応じて切り替え）
    /// - "tiny"  : openai_whisper-tiny
    /// - "base"  : openai_whisper-base
    static var bundledModelFolder: String {
        // 設定画面からの切り替えは廃止し、常に Base モデルを使用する
        return "openai_whisper-base"
    }
    
    /// 設定画面でモデルを変更したときに呼び出す
    /// 次回 recognize() 時に新しいモデルで再初期化される
    func invalidateModel() {
        whisperKit = nil
        loadedModelFolder = nil
        print("WhisperRecognition: モデルキャッシュを破棄しました（次回再ロード）")
    }

    init() {}

    func requestAuthorization() async -> Bool {
        return true
    }

    /// 仅接受本地音频文件 URL；远程下载由上层（Coordinator/ViewModel）完成后再传入。
    func recognize(audioURL: URL) async throws -> [RecognitionSegment] {
        guard audioURL.isFileURL else {
            throw NSError(domain: "WhisperRecognition", code: -1, userInfo: [NSLocalizedDescriptionKey: String(localized: "podcast_link_unresolvable")])
        }
        let localURL = audioURL

        let whisper = try await getOrInitWhisperKit()
        var options = DecodingOptions()
        options.task = .transcribe
        let preferJapanese = UserDefaults.standard.object(forKey: Self.preferJapaneseDefaultsKey) as? Bool ?? true
        if preferJapanese {
            options.language = "ja"
        }
        options.noSpeechThreshold = 0.8

        print("WhisperRecognition: 推論実行中 (\(localURL.lastPathComponent)) 言語=\(preferJapanese ? "ja" : "auto") モデル=\(Self.bundledModelFolder)...")
        let results = try await whisper.transcribe(audioPath: localURL.path, decodeOptions: options)

        var allSegments: [RecognitionSegment] = []
        for result in results {
            for segment in result.segments {
                let cleanedText = Self.cleanWhisperText(segment.text)
                if !cleanedText.isEmpty {
                    let isJapanese = Self.isLikelyJapanese(cleanedText)
                    allSegments.append(RecognitionSegment(
                        text: cleanedText,
                        startTime: Double(segment.start),
                        endTime: Double(segment.end),
                        confidence: 1.0,
                        isJapanese: isJapanese
                    ))
                }
            }
        }
        let processedSegments = Self.mergeShortSegments(allSegments)
        print("WhisperRecognition: 認識完了 セグメント数=\(processedSegments.count)")
        return processedSegments
    }
    
    private func getOrInitWhisperKit() async throws -> WhisperKit {
        // 設定が変わっていたらキャッシュを破棄して再ロード
        if let whisper = whisperKit, loadedModelFolder == Self.bundledModelFolder {
            return whisper
        }
        whisperKit = nil
        
        // App Bundle 内のモデルパスを取得
        let modelPath = Self.bundledModelPath()
        
        if let modelPath = modelPath {
            print("WhisperRecognition: バンドル同梱モデルを使用: \(modelPath)")
            let config = WhisperKitConfig(
                model: Self.bundledModelFolder,
                modelFolder: modelPath,
                download: false  // バンドル済みモデルのみ使用する
            )
            let whisper = try await WhisperKit(config)
            self.whisperKit = whisper
            self.loadedModelFolder = Self.bundledModelFolder
            print("WhisperRecognition: モデル初期化完了（ローカル \(Self.bundledModelFolder)）✅")
            return whisper
        } else {
            // バンドルにモデルがない場合はオンラインダウンロードにフォールバック
            print("WhisperRecognition: バンドルにモデルが見つかりません、ダウンロードを試みます...")
            let whisper = try await WhisperKit()
            self.whisperKit = whisper
            self.loadedModelFolder = Self.bundledModelFolder
            print("WhisperRecognition: モデル初期化完了（ダウンロード）✅")
            return whisper
        }
    }
    
    /// App Bundle 内のモデルフォルダパスを取得する
    /// モデルは WhisperModels/openai_whisper-base/ に格納され、MelSpectrogram.mlmodelc 等はこの直下にある
    /// WhisperKit の modelFolder は .mlmodelc が直下にあるディレクトリ（例: .../openai_whisper-base）を指す必要がある
    private static func bundledModelPath() -> String? {
        guard let modelsURL = Bundle.main.resourceURL?.appendingPathComponent("WhisperModels") else {
            return nil
        }
        let modelDir = modelsURL.appendingPathComponent(bundledModelFolder)
        let configPath = modelDir.appendingPathComponent("config.json").path
        if FileManager.default.fileExists(atPath: configPath) {
            return modelDir.path
        }
        return nil
    }
    
    /// 判断该句是否主要为日语（含平假名/片假名/汉字）。用于标记非日语句以便跳过注音。
    static func isLikelyJapanese(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return true }
        for ch in t.unicodeScalars {
            switch ch.value {
            case 0x3040..<0x30A0: return true   // 平假名
            case 0x30A0..<0x3100: return true   // 片假名
            case 0x4E00..<0xA000: return true   // CJK 统一汉字
            default: break
            }
        }
        return false
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
    
    // MARK: - セグメント後処理（断句の簡易最適化）
    
    /// Whisper のセグメントをそのまま使うと、短すぎるフレーズが細かく分かれて字幕が読みにくいことがある。
    /// ここでは「極端に短いセグメントかつ終止符で終わらないもの」を次のセグメントと結合して、
    /// なるべく自然な文単位に近づける。
    static func mergeShortSegments(_ segments: [RecognitionSegment]) -> [RecognitionSegment] {
        guard !segments.isEmpty else { return [] }
        
        var merged: [RecognitionSegment] = []
        let minDuration: Double = 0.7
        let endPunctuations: Set<Character> = ["。", "！", "？", "!", "?"]
        
        var buffer = segments[0]
        
        func flushBuffer() {
            merged.append(buffer)
        }
        
        for seg in segments.dropFirst() {
            let duration = buffer.endTime - buffer.startTime
            let lastChar = buffer.text.trimmingCharacters(in: .whitespacesAndNewlines).last
            
            if duration < minDuration, let last = lastChar, !endPunctuations.contains(last) {
                buffer = RecognitionSegment(
                    text: buffer.text + seg.text,
                    startTime: buffer.startTime,
                    endTime: seg.endTime,
                    confidence: min(buffer.confidence, seg.confidence),
                    isJapanese: buffer.isJapanese || seg.isJapanese
                )
            } else {
                flushBuffer()
                buffer = seg
            }
        }
        
        flushBuffer()
        return merged
    }
}

#else

/// WhisperKit 未導入時のフォールバック
final class WhisperSpeechRecognitionService: SpeechRecognitionServiceProtocol {

    /// 判断该句是否主要为日语（与 canImport(WhisperKit) 分支逻辑一致，供 SRT 等路径使用）
    static func isLikelyJapanese(_ text: String) -> Bool {
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
