//
//  Models.swift
//  YomiPlay
//
//  音声学習アプリのデータモデル定義
//

import Foundation

// MARK: - 音声ソース

/// 音声ファイルの種別
enum AudioSourceType: String, Codable {
    case local   // ローカルファイル
    case remote  // リモートURL
}

/// 音声ソース情報
struct AudioSource: Identifiable, Codable, Hashable {
    let id: UUID
    let type: AudioSourceType
    var localURL: URL?
    var remoteURL: URL?
    /// Documents ディレクトリからの相対パス（再起動後も再生可能にするため）
    var relativeFilePath: String?
    var title: String
    var duration: TimeInterval?
    /// SRT ファイルの Documents からの相対パス（インポート時に設定）
    var srtRelativeFilePath: String?
    /// 元の動画ファイルの Documents からの相対パス（動画インポート時に設定）
    var videoRelativeFilePath: String?
    /// インポート時に紐付けたいフォルダID（nil = デフォルト分组）
    var folderId: UUID?
    
    init(
        id: UUID = UUID(),
        type: AudioSourceType,
        localURL: URL? = nil,
        remoteURL: URL? = nil,
        relativeFilePath: String? = nil,
        title: String = "",
        duration: TimeInterval? = nil,
        srtRelativeFilePath: String? = nil,
        videoRelativeFilePath: String? = nil,
        folderId: UUID? = nil
    ) {
        self.id = id
        self.type = type
        self.localURL = localURL
        self.remoteURL = remoteURL
        self.relativeFilePath = relativeFilePath
        self.title = title
        self.duration = duration
        self.srtRelativeFilePath = srtRelativeFilePath
        self.videoRelativeFilePath = videoRelativeFilePath
        self.folderId = folderId
    }
    
    /// 再生用URLを返す（ローカルは相対パスから再構築を優先）
    var playbackURL: URL? {
        switch type {
        case .local:
            if let rel = relativeFilePath, !rel.isEmpty,
               let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let resolved = docs.appendingPathComponent(rel)
                if FileManager.default.fileExists(atPath: resolved.path) {
                    return resolved
                }
            }
            return localURL
        case .remote:
            return remoteURL
        }
    }
    
    /// 元の動画ファイルの URL を返す（Documents 内の相対パスから解決）
    var videoPlaybackURL: URL? {
        guard let rel = videoRelativeFilePath, !rel.isEmpty,
              let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        else { return nil }
        let resolved = docs.appendingPathComponent(rel)
        return FileManager.default.fileExists(atPath: resolved.path) ? resolved : nil
    }
    
    /// SRT ファイルの URL を返す（Documents 内の相対パスから解決）
    var srtURL: URL? {
        guard let rel = srtRelativeFilePath, !rel.isEmpty,
              let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        else { return nil }
        let resolved = docs.appendingPathComponent(rel)
        return FileManager.default.fileExists(atPath: resolved.path) ? resolved : nil
    }
}

// MARK: - 振り仮名トークン

/// 詞性（品詞）— 用于按词性下划线等展示
enum PartOfSpeech: String, Codable, Equatable {
    case particle  // 助詞
    case verb      // 動詞
    case noun      // 名詞
    case other
}

/// テキストの各トークン（漢字＋読み、またはそのまま表示する文字）
struct FuriganaToken: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let surface: String   // 表示テキスト（例：「漢字」）
    let reading: String   // 読み（例：「かんじ」）
    let romaji: String    // ローマ字（例：「kanji」）
    let isKanji: Bool     // 漢字を含むかどうか
    /// カタカナのみで構成されるトークンかどうか（外来語判定用）
    let isKatakana: Bool
    /// 外来語の英語原綴り（例：「コンピューター」→「computer」）。該当しない場合は nil
    let englishMeaning: String?
    /// 詞級時間（卡拉OK 逐詞高亮用）。nil 時由 UI 按句內比例推算
    let startTime: TimeInterval?
    let endTime: TimeInterval?
    /// 詞性（用于按词性下划线）。nil 時不畫下劃線
    let partOfSpeech: PartOfSpeech?
    
    init(
        id: UUID = UUID(),
        surface: String,
        reading: String = "",
        romaji: String = "",
        isKanji: Bool = false,
        isKatakana: Bool = false,
        englishMeaning: String? = nil,
        startTime: TimeInterval? = nil,
        endTime: TimeInterval? = nil,
        partOfSpeech: PartOfSpeech? = nil
    ) {
        self.id = id
        self.surface = surface
        self.reading = reading
        self.romaji = romaji
        self.isKanji = isKanji
        self.isKatakana = isKatakana
        self.englishMeaning = englishMeaning
        self.startTime = startTime
        self.endTime = endTime
        self.partOfSpeech = partOfSpeech
    }
}

// MARK: - 字幕セグメント

/// 一文の字幕データ（タイムスタンプ・テキスト・振り仮名を含む）
struct TranscriptSegment: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var startTime: TimeInterval   // 開始時間（秒）
    var endTime: TimeInterval     // 終了時間（秒）
    var originalText: String      // 元のテキスト（ユーザーが編集可能）
    var tokens: [FuriganaToken]   // 振り仮名トークンの配列
    var confidence: Float?        // 認識信頼度（オプション）
    /// true の場合、振り仮名・ローマ字を表示しない（中国語など日本語以外のセグメント用）
    var skipFurigana: Bool
    /// 翻訳済みテキスト（ユーザーが翻訳機能を実行したときに設定される）
    var translatedText: String?
    /// 用户手动注音覆盖（可选）。有值时优先于自动分词 tokens 展示。
    var userTokenOverrides: [FuriganaToken]?
    /// 本句 `originalText` 的书写/识别语言（Whisper 主标签如 ja/en/zh）。跟读转写优先用此值；nil 时用全局识别语言设置。
    var originalTextLanguageCode: String?
    
    init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        endTime: TimeInterval,
        originalText: String,
        tokens: [FuriganaToken] = [],
        confidence: Float? = nil,
        skipFurigana: Bool = false,
        translatedText: String? = nil,
        userTokenOverrides: [FuriganaToken]? = nil,
        originalTextLanguageCode: String? = nil
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.originalText = originalText
        self.tokens = tokens
        self.confidence = confidence
        self.skipFurigana = skipFurigana
        self.translatedText = translatedText
        self.userTokenOverrides = userTokenOverrides
        self.originalTextLanguageCode = originalTextLanguageCode
    }

    /// 兼容旧版本调用点：历史参数 `manualFuriganaText` 已由 `userTokenOverrides` 取代
    @_disfavoredOverload
    init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        endTime: TimeInterval,
        originalText: String,
        tokens: [FuriganaToken] = [],
        confidence: Float? = nil,
        skipFurigana: Bool = false,
        translatedText: String? = nil,
        manualFuriganaText: String? = nil,
        originalTextLanguageCode: String? = nil
    ) {
        // 旧字段为整句注音文本，不再参与新展示逻辑；这里仅保留链接兼容。
        let _ = manualFuriganaText
        self.init(
            id: id,
            startTime: startTime,
            endTime: endTime,
            originalText: originalText,
            tokens: tokens,
            confidence: confidence,
            skipFurigana: skipFurigana,
            translatedText: translatedText,
            userTokenOverrides: nil,
            originalTextLanguageCode: originalTextLanguageCode
        )
    }
    
    /// 指定時刻がこのセグメントの範囲内かどうか
    func contains(time: TimeInterval) -> Bool {
        return time >= startTime && time < endTime
    }
}

// MARK: - 学習フォルダ（ZIP インポート等でグループ化）

/// 記録をグループ化するフォルダ（ZIP インポート時に自動作成）
struct TranscriptFolder: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    let createdAt: Date
    
    init(id: UUID = UUID(), name: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

// MARK: - 字幕ドキュメント

/// 文档导入时自动翻译的执行结果。仅作 UI 提示用，不影响字幕本身的可用性。
enum TranslationStatus: String, Codable, Sendable {
    /// 用户已开启翻译且全部翻译成功
    case success
    /// 用户已开启翻译但运行时失败（网络 / 语言包未就绪等），字幕仍可正常使用
    case failed
    /// 用户未开启翻译，本次跳过
    case skipped
}

/// 音声ファイルに対応する字幕全体
struct TranscriptDocument: Identifiable, Codable, Hashable {
    let id: UUID
    var source: AudioSource       // 音声ソース情報（タイトル編集可能）
    var segments: [TranscriptSegment]
    let createdAt: Date
    /// 最後に再生した位置（秒）。次回開いたときに復元する
    var lastPlaybackPosition: TimeInterval?
    /// 所属フォルダ ID（nil の場合は未グループ）
    var folderId: UUID?
    /// 识别源语言为英/中等（非日语、非自动）时保存为 true：分句均为非日文注音模式，播放页默认关闭假名/罗马字/英译注音
    var isNonJapaneseRecognitionSource: Bool?
    /// 导入时自动翻译的执行结果。`nil` 视为「老文档 / 未知」，UI 不展示。
    var translationStatus: TranslationStatus?

    init(
        id: UUID = UUID(),
        source: AudioSource,
        segments: [TranscriptSegment] = [],
        createdAt: Date = Date(),
        lastPlaybackPosition: TimeInterval? = nil,
        folderId: UUID? = nil,
        isNonJapaneseRecognitionSource: Bool? = nil,
        translationStatus: TranslationStatus? = nil
    ) {
        self.id = id
        self.source = source
        self.segments = segments
        self.createdAt = createdAt
        self.lastPlaybackPosition = lastPlaybackPosition
        self.folderId = folderId
        self.isNonJapaneseRecognitionSource = isNonJapaneseRecognitionSource
        self.translationStatus = translationStatus
    }
}

// MARK: - 処理状態

/// 处理流程发生错误时所处的"环节"。用于在 UI 上准确告诉用户是哪一步失败的。
enum ProcessingStage: String, Equatable, Sendable {
    case permission       // 授权
    case resolveRemote    // 解析远程链接
    case downloadRemote   // 下载远程音频
    case loadAudio        // 读取/落地本地音频
    case parseSRT         // 解析字幕文件
    case recognize        // 语音识别
    case furigana         // 生成注音
    case translate        // 翻译
    case unknown          // 未明确归类

    /// 该环节失败时显示的标题（如「下载播客失败」「语音识别失败」）
    func failureTitle(locale: Locale) -> String {
        switch self {
        case .permission: return String(localized: LocalizedStringResource("stage_failure_permission", locale: locale))
        case .resolveRemote: return String(localized: LocalizedStringResource("stage_failure_resolve_remote", locale: locale))
        case .downloadRemote: return String(localized: LocalizedStringResource("stage_failure_download_remote", locale: locale))
        case .loadAudio: return String(localized: LocalizedStringResource("stage_failure_load_audio", locale: locale))
        case .parseSRT: return String(localized: LocalizedStringResource("stage_failure_parse_srt", locale: locale))
        case .recognize: return String(localized: LocalizedStringResource("stage_failure_recognize", locale: locale))
        case .furigana: return String(localized: LocalizedStringResource("stage_failure_furigana", locale: locale))
        case .translate: return String(localized: LocalizedStringResource("stage_failure_translate", locale: locale))
        case .unknown: return String(localized: LocalizedStringResource("error", locale: locale))
        }
    }

    /// 该 stage 对应到流水线中"正在进行的 ProcessingState"，用于在错误屏幕里把对应步骤条标红
    var matchingState: ProcessingState? {
        switch self {
        case .resolveRemote: return .resolvingRemoteSource
        case .downloadRemote: return .downloadingPodcast
        case .loadAudio: return .loadingAudio
        case .parseSRT: return .parsingSRT
        case .recognize: return .recognizing
        case .furigana: return .generatingFurigana
        case .translate: return .translating
        case .permission, .unknown: return nil
        }
    }
}

/// 音声処理の進行状態
enum ProcessingState: Equatable {
    case idle
    case preparing
    case loadingAudio
    case resolvingRemoteSource
    case downloadingPodcast
    case recognizing
    case parsingSRT
    case generatingFurigana
    case translating
    case completed
    /// 错误：包含「失败发生在哪个环节」+ 用户可见消息。
    case error(stage: ProcessingStage, message: String)

    /// 使用指定 locale 的本地化文案（随应用内语言切换）
    func displayText(locale: Locale) -> String {
        switch self {
        case .idle: return String(localized: LocalizedStringResource("preparing", locale: locale))
        case .preparing: return String(localized: LocalizedStringResource("preparing", locale: locale))
        case .loadingAudio: return String(localized: LocalizedStringResource("loading_audio_2", locale: locale))
        case .resolvingRemoteSource: return String(localized: LocalizedStringResource("resolving_podcast_link", locale: locale))
        case .downloadingPodcast: return String(localized: LocalizedStringResource("downloading_podcast_audio", locale: locale))
        case .recognizing: return String(localized: LocalizedStringResource("recognizing_speech", locale: locale))
        case .parsingSRT: return String(localized: LocalizedStringResource("parsing_subtitles", locale: locale))
        case .generatingFurigana: return String(localized: LocalizedStringResource("generating_phonetic_subtitles", locale: locale))
        case .translating: return String(localized: LocalizedStringResource("translating_subtitles", locale: locale))
        case .completed: return String(localized: LocalizedStringResource("done", locale: locale))
        case .error(let stage, let message):
            // 错误屏幕主标题：「下载播客失败：xxx」/「语音识别失败：xxx」等
            return stage.failureTitle(locale: locale) + ": " + message
        }
    }

    /// 仅返回错误主消息（不带「<阶段>失败」前缀），用于错误屏幕里独立展示
    var errorMessage: String? {
        if case .error(_, let message) = self { return message }
        return nil
    }

    /// 错误时的归类阶段（非 error 状态返回 nil）
    var errorStage: ProcessingStage? {
        if case .error(let stage, _) = self { return stage }
        return nil
    }

    var isProcessing: Bool {
        switch self {
        case .preparing, .loadingAudio, .resolvingRemoteSource, .downloadingPodcast, .recognizing, .parsingSRT, .generatingFurigana, .translating:
            return true
        default:
            return false
        }
    }
}
