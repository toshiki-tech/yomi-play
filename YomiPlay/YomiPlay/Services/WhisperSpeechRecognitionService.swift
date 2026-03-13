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
    private var initFailed = false
    private let fallback = AppleSpeechRecognitionService()
    
    /// UserDefaults に保存するモデル選択キー
    static let modelVariantDefaultsKey = "whisperModelVariant"
    
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
        initFailed = false
        print("WhisperRecognition: モデルキャッシュを破棄しました（次回再ロード）")
    }
    
    init() {}
    
    func requestAuthorization() async -> Bool {
        return true
    }
    
    func recognize(audioURL: URL) async throws -> [RecognitionSegment] {
        if initFailed {
            print("WhisperRecognition: 前回失敗のため Apple Speech にフォールバック")
            return try await fallback.recognize(audioURL: audioURL)
        }
        
        // リモートURLの場合はダウンロードする
        let localURL: URL
        let isRemote = !audioURL.isFileURL
        
        if isRemote {
            print("WhisperRecognition: リモートURLをダウンロード中: \(audioURL)")
            localURL = try await downloadRemoteAudio(from: audioURL)
        } else {
            localURL = audioURL
        }
        
        defer {
            if isRemote {
                try? FileManager.default.removeItem(at: localURL)
                print("WhisperRecognition: 一時ファイルを削除しました")
            }
        }
        
        do {
            let whisper = try await getOrInitWhisperKit()
            
            var options = DecodingOptions()
            // language を指定しないことで、多言語混在の音声でも自動言語検出に任せる
            options.task = .transcribe
            // デフォルト (0.6) より高めに設定して、無音と誤判定されるセグメントを減らす
            // 値を上げるほど「無音でも無理やり認識する」方向になるので 0.8 程度が無難
            options.noSpeechThreshold = 0.8
            
            print("WhisperRecognition: 推論実行中 (\(localURL.lastPathComponent)) モデル=\(Self.bundledModelFolder)...")
            let results = try await whisper.transcribe(audioPath: localURL.path, decodeOptions: options)
            
            var allSegments: [RecognitionSegment] = []
            
            for result in results {
                let segments = result.segments
                for segment in segments {
                    let cleanedText = Self.cleanWhisperText(segment.text)
                    if !cleanedText.isEmpty {
                        allSegments.append(
                            RecognitionSegment(
                                text: cleanedText,
                                startTime: Double(segment.start),
                                endTime: Double(segment.end),
                                confidence: 1.0
                            )
                        )
                    }
                }
            }
            
            // Whisper の生セグメントを少し整形して、字幕としてより自然な断句に近づける
            let processedSegments = Self.mergeShortSegments(allSegments)
            
            print("WhisperRecognition: 認識完了 セグメント数=\(processedSegments.count) (merged from \(allSegments.count))")
            return processedSegments
            
        } catch {
            print("WhisperRecognition: エラー \(error.localizedDescription) → フォールバック")
            // initFailed は WhisperKit 固有のエラー（モデル読み込み失敗など）の場合のみセットする
            // ネットワークエラーなどは含めないほうが良いが、一旦単純化して保持
            if (error as NSError).domain == NSURLErrorDomain {
                throw error // ネットワークエラーはそのまま投げる
            }
            initFailed = true
            return try await fallback.recognize(audioURL: audioURL)
        }
    }
    
    private func downloadRemoteAudio(from url: URL) async throws -> URL {
        let (tempURL, response) = try await URLSession.shared.download(from: url)
        
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw NSError(domain: "WhisperRecognition", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP error: \(httpResponse.statusCode)"])
        }
        
        let destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "_" + url.lastPathComponent)
        try FileManager.default.moveItem(at: tempURL, to: destinationURL)
        return destinationURL
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
    /// モデルは WhisperModels/ フォルダに格納されている
    /// WhisperKit は modelFolder として親ディレクトリ（WhisperModels/）のパスを期待する
    private static func bundledModelPath() -> String? {
        guard let modelsURL = Bundle.main.resourceURL?.appendingPathComponent("WhisperModels") else {
            return nil
        }
        let modelDir = modelsURL.appendingPathComponent(bundledModelFolder)
        let configPath = modelDir.appendingPathComponent("config.json").path
        if FileManager.default.fileExists(atPath: configPath) {
            return modelsURL.path
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
                    confidence: min(buffer.confidence, seg.confidence)
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
