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
    
    init(
        id: UUID = UUID(),
        type: AudioSourceType,
        localURL: URL? = nil,
        remoteURL: URL? = nil,
        relativeFilePath: String? = nil,
        title: String = "",
        duration: TimeInterval? = nil,
        srtRelativeFilePath: String? = nil,
        videoRelativeFilePath: String? = nil
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
    var startTime: TimeInterval   // 開始時間（秒）
    var endTime: TimeInterval     // 終了時間（秒）
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
    
    init(
        id: UUID = UUID(),
        source: AudioSource,
        segments: [TranscriptSegment] = [],
        createdAt: Date = Date(),
        lastPlaybackPosition: TimeInterval? = nil,
        folderId: UUID? = nil
    ) {
        self.id = id
        self.source = source
        self.segments = segments
        self.createdAt = createdAt
        self.lastPlaybackPosition = lastPlaybackPosition
        self.folderId = folderId
    }
}

// MARK: - 処理状態

/// 音声処理の進行状態
enum ProcessingState: Equatable {
    case idle                    // 未開始
    case loadingAudio            // 音声読み込み中
    case recognizing             // 音声認識中
    case parsingSRT              // SRT 解析中
    case generatingFurigana      // 振り仮名生成中
    case completed               // 完了
    case error(String)           // エラー
    
    var displayText: String {
        switch self {
        case .idle:                return String(localized: "preparing")
        case .loadingAudio:        return String(localized: "loading_audio_2")
        case .recognizing:         return String(localized: "recognizing_speech")
        case .parsingSRT:          return String(localized: "parsing_subtitles")
        case .generatingFurigana:  return String(localized: "generating_furigana")
        case .completed:           return String(localized: "done")
        case .error(let message):  return String(localized: "error") + ": " + message
        }
    }
    
    var isProcessing: Bool {
        switch self {
        case .loadingAudio, .recognizing, .parsingSRT, .generatingFurigana:
            return true
        default:
            return false
        }
    }
}
