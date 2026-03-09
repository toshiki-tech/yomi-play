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
    
    init(
        id: UUID = UUID(),
        type: AudioSourceType,
        localURL: URL? = nil,
        remoteURL: URL? = nil,
        relativeFilePath: String? = nil,
        title: String = "",
        duration: TimeInterval? = nil
    ) {
        self.id = id
        self.type = type
        self.localURL = localURL
        self.remoteURL = remoteURL
        self.relativeFilePath = relativeFilePath
        self.title = title
        self.duration = duration
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
}

// MARK: - 振り仮名トークン

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
    
    init(
        id: UUID = UUID(),
        surface: String,
        reading: String = "",
        romaji: String = "",
        isKanji: Bool = false,
        isKatakana: Bool = false,
        englishMeaning: String? = nil
    ) {
        self.id = id
        self.surface = surface
        self.reading = reading
        self.romaji = romaji
        self.isKanji = isKanji
        self.isKatakana = isKatakana
        self.englishMeaning = englishMeaning
    }
}

// MARK: - 字幕セグメント

/// 一文の字幕データ（タイムスタンプ・テキスト・振り仮名を含む）
struct TranscriptSegment: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let startTime: TimeInterval   // 開始時間（秒）
    let endTime: TimeInterval     // 終了時間（秒）
    var originalText: String      // 元のテキスト（ユーザーが編集可能）
    var tokens: [FuriganaToken]   // 振り仮名トークンの配列
    var confidence: Float?        // 認識信頼度（オプション）
    /// true の場合、振り仮名・ローマ字を表示しない（中国語など日本語以外のセグメント用）
    var skipFurigana: Bool
    /// 翻訳済みテキスト（ユーザーが翻訳機能を実行したときに設定される）
    var translatedText: String?
    
    init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        endTime: TimeInterval,
        originalText: String,
        tokens: [FuriganaToken] = [],
        confidence: Float? = nil,
        skipFurigana: Bool = false,
        translatedText: String? = nil
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.originalText = originalText
        self.tokens = tokens
        self.confidence = confidence
        self.skipFurigana = skipFurigana
        self.translatedText = translatedText
    }
    
    /// 指定時刻がこのセグメントの範囲内かどうか
    func contains(time: TimeInterval) -> Bool {
        return time >= startTime && time < endTime
    }
}

// MARK: - 字幕ドキュメント

/// 音声ファイルに対応する字幕全体
struct TranscriptDocument: Identifiable, Codable, Hashable {
    let id: UUID
    var source: AudioSource       // 音声ソース情報（タイトル編集可能）
    var segments: [TranscriptSegment]
    let createdAt: Date
    /// 最後に再生した位置（秒）。次回開いたときに復元する
    var lastPlaybackPosition: TimeInterval?
    
    init(
        id: UUID = UUID(),
        source: AudioSource,
        segments: [TranscriptSegment] = [],
        createdAt: Date = Date(),
        lastPlaybackPosition: TimeInterval? = nil
    ) {
        self.id = id
        self.source = source
        self.segments = segments
        self.createdAt = createdAt
        self.lastPlaybackPosition = lastPlaybackPosition
    }
}

// MARK: - 処理状態

/// 音声処理の進行状態
enum ProcessingState: Equatable {
    case idle                    // 未開始
    case loadingAudio            // 音声読み込み中
    case recognizing             // 音声認識中
    case generatingFurigana      // 振り仮名生成中
    case completed               // 完了
    case error(String)           // エラー
    
    var displayText: String {
        switch self {
        case .idle:                return String(localized: "准备中...")
        case .loadingAudio:        return String(localized: "正在加载音频...")
        case .recognizing:         return String(localized: "正在识别语音...")
        case .generatingFurigana:  return String(localized: "正在生成假名注音...")
        case .completed:           return String(localized: "完成！")
        case .error(let message):  return String(localized: "错误") + ": " + message
        }
    }
    
    var isProcessing: Bool {
        switch self {
        case .loadingAudio, .recognizing, .generatingFurigana:
            return true
        default:
            return false
        }
    }
}
