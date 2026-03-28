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
    
    /// UserDefaults に保存するモデル選択キー（値: "tiny" | "base" | "small" | "medium" | "large"）
    static let modelVariantDefaultsKey = "whisperModelVariant"
    /// UserDefaults に保存する認識言語キー（値: "ja" | "en" | "zh"）。デフォルトは日本語。
    static let sourceLanguageDefaultsKey = "whisperSourceLanguage"

    /// 识别模式：Tiny / Base / Small / Medium / Large，与 Whisper 模型尺寸一致
    enum RecognitionMode: String, CaseIterable {
        case tiny = "tiny"
        case base = "base"
        case small = "small"
        case medium = "medium"
        case large = "large"
        var folderName: String {
            switch self {
            case .tiny: return "openai_whisper-tiny"
            case .base: return "openai_whisper-base"
            case .small: return "openai_whisper-small"
            case .medium: return "openai_whisper-medium"
            case .large: return "openai_whisper-large-v3"
            }
        }
    }

    /// 根据设备内存推荐可流畅运行的模型档位（首次安装时作为默认值）
    static var recommendedModeForDevice: RecognitionMode {
        let mem = ProcessInfo.processInfo.physicalMemory
        let gb = Double(mem) / (1024.0 * 1024.0 * 1024.0)
        if gb < 3 { return .tiny }
        if gb < 4 { return .base }
        if gb < 6 { return .small }
        if gb < 8 { return .medium }
        return .large
    }

    /// 迁移旧值并确保 UserDefaults 中有有效选择；首次安装时写入设备推荐档位
    static func ensureModelVariantInitialized() {
        let ud = UserDefaults.standard
        var raw = ud.string(forKey: modelVariantDefaultsKey)
        let validRaw = Set(RecognitionMode.allCases.map(\.rawValue))

        if let r = raw, !validRaw.contains(r) {
            let migrated: String
            switch r {
            case "fast": migrated = "base"
            case "standard": migrated = "small"
            case "high": migrated = "medium"
            case "large": migrated = "large"
            default: migrated = recommendedModeForDevice.rawValue
            }
            raw = migrated
            ud.set(migrated, forKey: modelVariantDefaultsKey)
        }
        if raw == nil {
            let recommended = recommendedModeForDevice
            ud.set(recommended.rawValue, forKey: modelVariantDefaultsKey)
        }
    }

    /// 当前设置对应的同梱モデルフォルダ名
    private static var bundledModelFolder: String {
        Self.ensureModelVariantInitialized()
        let raw = UserDefaults.standard.string(forKey: Self.modelVariantDefaultsKey) ?? Self.recommendedModeForDevice.rawValue
        let mode = RecognitionMode(rawValue: raw) ?? .small
        return mode.folderName
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
    func recognize(audioURL: URL, preferredLanguageCode: String?) async throws -> [RecognitionSegment] {
        guard audioURL.isFileURL else {
            throw NSError(domain: "WhisperRecognition", code: -1, userInfo: [NSLocalizedDescriptionKey: String(localized: "podcast_link_unresolvable")])
        }
        let localURL = audioURL

        let whisper = try await getOrInitWhisperKit()
        var options = DecodingOptions()
        // 必须使用转写（原文输出），禁止使用 translation（会译成英文）
        options.task = .transcribe
        // 根据设置中的识别语言转写；跟读等场景可传入本句 preferredLanguageCode 覆盖全局。
        // - "ja" / "en" / "zh"：固定语言
        // - "auto" 或未设置：让 Whisper 自动检测语言（不显式指定）
        let global = UserDefaults.standard.string(forKey: Self.sourceLanguageDefaultsKey) ?? "ja"
        let trimmed = preferredLanguageCode?.trimmingCharacters(in: .whitespacesAndNewlines)
        let lang: String
        if let t = trimmed, !t.isEmpty {
            lang = t
        } else {
            lang = global
        }
        let forceNonJapaneseSegments = Self.forcesNonJapaneseSegments(lang: lang)
        if lang != "auto" {
            options.language = lang
        }
        options.noSpeechThreshold = 0.8
        print("WhisperRecognition: 推論実行中 (\(localURL.lastPathComponent)) 言語=\(lang) モデル=\(Self.bundledModelFolder)...")
        let results = try await whisper.transcribe(audioPath: localURL.path, decodeOptions: options)

        var allSegments: [RecognitionSegment] = []
        for result in results {
            for segment in result.segments {
                let cleanedText = Self.cleanWhisperText(segment.text)
                if !cleanedText.isEmpty {
                    let isJapanese = forceNonJapaneseSegments ? false : Self.isLikelyJapanese(cleanedText)
                    let words = segment.words?.map {
                        WordTimingInfo(
                            word: $0.word,
                            start: TimeInterval($0.start),
                            end: TimeInterval($0.end)
                        )
                    }
                    allSegments.append(RecognitionSegment(
                        text: cleanedText,
                        startTime: Double(segment.start),
                        endTime: Double(segment.end),
                        confidence: 1.0,
                        isJapanese: isJapanese,
                        wordTimings: words
                    ))
                }
            }
        }
        let processedSegments = Self.mergeShortSegments(allSegments)
        print("WhisperRecognition: 認識完了 セグメント数=\(processedSegments.count)")
        return processedSegments
    }
    
    /// 识别语言为日语或自动时，按文本判定是否日语；为英/中等固定语言时整段视为非日语（注音流程会跳过）
    static func forcesNonJapaneseSegments(lang: String) -> Bool {
        if lang == "ja" || lang == "auto" { return false }
        return true
    }

    /// 写入字幕句的原文语言码（与识别设置、分句文本一致）。`nil` 表示未知，跟读时回退全局设置。
    static func storedOriginalTextLanguageCode(recognitionUserSetting: String, lineLooksJapanese: Bool) -> String? {
        let lang = recognitionUserSetting
        if forcesNonJapaneseSegments(lang: lang) {
            return lang == "auto" ? nil : lang
        }
        switch lang {
        case "auto": return lineLooksJapanese ? "ja" : "en"
        case "ja": return lineLooksJapanese ? "ja" : "en"
        case "en", "zh": return lang
        default: return lang == "auto" ? nil : lang
        }
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
    
    /// 指定した認識モードのモデルが Bundle 内に存在するか（极速/轻量/标准 は通常同梱、高精度/超大 は同梱しない場合あり）
    static func isModelAvailableLocally(_ mode: RecognitionMode) -> Bool {
        modelPath(for: mode) != nil
    }
    
    /// 高精度/超大モデルのダウンロード時の目安サイズ（確認ダイアログ用）。同梱モデルには使わない。
    static func downloadSizeDescription(for mode: RecognitionMode) -> String {
        switch mode {
        case .medium: return String(localized: "recognition_model_size_medium")
        case .large: return String(localized: "recognition_model_size_large")
        default: return ""
        }
    }
    
    /// 指定モード用の Bundle 内モデルディレクトリパス（存在しなければ nil）
    private static func modelPath(for mode: RecognitionMode) -> String? {
        guard let modelsURL = Bundle.main.resourceURL?.appendingPathComponent("WhisperModels") else {
            return nil
        }
        let folderName = mode.folderName
        let modelDir = modelsURL.appendingPathComponent(folderName)
        let configPath = modelDir.appendingPathComponent("config.json").path
        guard FileManager.default.fileExists(atPath: configPath) else { return nil }
        let encoderDir = modelDir.appendingPathComponent("AudioEncoder.mlmodelc")
        let hasEncoder = FileManager.default.fileExists(atPath: encoderDir.appendingPathComponent("model.mlmodel").path)
            || FileManager.default.fileExists(atPath: encoderDir.appendingPathComponent("model.mil").path)
        guard hasEncoder else { return nil }
        return modelDir.path
    }
    
    /// App Bundle 内のモデルフォルダパスを取得する（現在選択中のモード用）
    private static func bundledModelPath() -> String? {
        Self.ensureModelVariantInitialized()
        let raw = UserDefaults.standard.string(forKey: modelVariantDefaultsKey) ?? Self.recommendedModeForDevice.rawValue
        let mode = RecognitionMode(rawValue: raw) ?? .small
        return modelPath(for: mode)
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

    static func forcesNonJapaneseSegments(lang: String) -> Bool {
        if lang == "ja" || lang == "auto" { return false }
        return true
    }

    static func storedOriginalTextLanguageCode(recognitionUserSetting: String, lineLooksJapanese: Bool) -> String? {
        let lang = recognitionUserSetting
        if forcesNonJapaneseSegments(lang: lang) {
            return lang == "auto" ? nil : lang
        }
        switch lang {
        case "auto": return lineLooksJapanese ? "ja" : "en"
        case "ja": return lineLooksJapanese ? "ja" : "en"
        case "en", "zh": return lang
        default: return lang == "auto" ? nil : lang
        }
    }

    private let fallback = AppleSpeechRecognitionService()
    
    init() {
        print("WhisperRecognition: WhisperKit 未導入 → Apple Speech にフォールバック")
    }
    
    func requestAuthorization() async -> Bool {
        return await fallback.requestAuthorization()
    }
    
    func recognize(audioURL: URL, preferredLanguageCode: String?) async throws -> [RecognitionSegment] {
        return try await fallback.recognize(audioURL: audioURL, preferredLanguageCode: preferredLanguageCode)
    }
}

#endif
