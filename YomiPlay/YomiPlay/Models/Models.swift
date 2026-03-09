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
    
    init(
        id: UUID = UUID(),
        surface: String,
        reading: String = "",
        romaji: String = "",
        isKanji: Bool = false
    ) {
        self.id = id
        self.surface = surface
        self.reading = reading
        self.romaji = romaji
        self.isKanji = isKanji
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
    
    init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        endTime: TimeInterval,
        originalText: String,
        tokens: [FuriganaToken] = [],
        confidence: Float? = nil,
        skipFurigana: Bool = false
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.originalText = originalText
        self.tokens = tokens
        self.confidence = confidence
        self.skipFurigana = skipFurigana
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
        case .idle:                return "準備中..."
        case .loadingAudio:        return "音声を読み込み中..."
        case .recognizing:         return "音声を認識中..."
        case .generatingFurigana:  return "振り仮名を生成中..."
        case .completed:           return "完了！"
        case .error(let message):  return "エラー: \(message)"
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
