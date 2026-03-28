//
//  SpeechRecognitionService.swift
//  YomiPlay
//
//  音声認識サービス
//  SFSpeechRecognizerを使用した日本語音声認識の実装
//  長い音声ファイルは分割して認識する
//

import Foundation
import Speech
import AVFoundation

// MARK: - 認識結果

/// Whisper / Apple 共用的句级识别结果
struct RecognitionSegment {
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let confidence: Float
    /// 该句是否主要为日语（含平假名/片假名/汉字）。非日语句不生成注音。
    let isJapanese: Bool
    /// 可选的逐词时间戳（仅 Whisper 提供），用于更精确的卡拉 OK 高亮
    let wordTimings: [WordTimingInfo]?
    
    init(
        text: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        confidence: Float,
        isJapanese: Bool = true,
        wordTimings: [WordTimingInfo]? = nil
    ) {
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
        self.isJapanese = isJapanese
        self.wordTimings = wordTimings
    }
}

/// 轻量版 Word 时间信息，解耦 WhisperKit 的 WordTiming 类型
struct WordTimingInfo {
    let word: String
    let start: TimeInterval
    let end: TimeInterval
}

// MARK: - プロトコル定義

protocol SpeechRecognitionServiceProtocol: Sendable {
    func recognize(audioURL: URL, preferredLanguageCode: String?) async throws -> [RecognitionSegment]
    func requestAuthorization() async -> Bool
}

extension SpeechRecognitionServiceProtocol {
    func recognize(audioURL: URL) async throws -> [RecognitionSegment] {
        try await recognize(audioURL: audioURL, preferredLanguageCode: nil)
    }
}

// MARK: - Apple Speech Framework実装

/// SFSpeechRecognizerを使用した音声認識サービス
/// 長い音声は自動的に分割して認識する
final class AppleSpeechRecognitionService: SpeechRecognitionServiceProtocol {
    
    /// Apple の認識制限（秒）— 安全マージンを含めて50秒
    private let maxChunkDuration: TimeInterval = 50
    
    func requestAuthorization() async -> Bool {
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
    
    func recognize(audioURL: URL, preferredLanguageCode: String?) async throws -> [RecognitionSegment] {
        _ = preferredLanguageCode
        print("SpeechRecognition: 認識開始 URL=\(audioURL)")
        
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP")),
              recognizer.isAvailable else {
            throw RecognitionError.notAvailable
        }
        
        if audioURL.isFileURL {
            guard FileManager.default.fileExists(atPath: audioURL.path) else {
                throw RecognitionError.audioLoadFailed
            }
        }
        
        // 音声の長さを取得
        let asset = AVURLAsset(url: audioURL)
        let duration: TimeInterval
        do {
            let cmDuration = try await asset.load(.duration)
            duration = CMTimeGetSeconds(cmDuration)
        } catch {
            // 長さが取得できない場合は直接認識を試みる
            duration = 0
        }
        
        print("SpeechRecognition: 音声の長さ = \(String(format: "%.1f", duration))秒")
        
        // 短い音声（50秒以下）はそのまま認識
        if duration > 0 && duration <= maxChunkDuration {
            return try await recognizeSingle(audioURL: audioURL, recognizer: recognizer)
        }
        
        // 長い音声は分割して認識
        if duration > maxChunkDuration {
            return try await recognizeInChunks(audioURL: audioURL, totalDuration: duration, recognizer: recognizer)
        }
        
        // 長さ不明の場合はまず直接試み、失敗したら分割
        do {
            return try await recognizeSingle(audioURL: audioURL, recognizer: recognizer)
        } catch {
            print("SpeechRecognition: 直接認識失敗、分割認識を試みます: \(error)")
            // 長さを再取得して分割
            let assetRetry = AVURLAsset(url: audioURL)
            let durationRetry = try await CMTimeGetSeconds(assetRetry.load(.duration))
            if durationRetry > 0 {
                return try await recognizeInChunks(audioURL: audioURL, totalDuration: durationRetry, recognizer: recognizer)
            }
            throw error
        }
    }
    
    // MARK: - 単一ファイル認識
    
    private func recognizeSingle(audioURL: URL, recognizer: SFSpeechRecognizer) async throws -> [RecognitionSegment] {
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        
        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            
            recognizer.recognitionTask(with: request) { result, error in
                guard !hasResumed else { return }
                
                if let error = error {
                    hasResumed = true
                    print("SpeechRecognition: エラー: \(error.localizedDescription)")
                    continuation.resume(throwing: RecognitionError.recognitionFailed(error.localizedDescription))
                    return
                }
                
                guard let result = result else { return }
                
                if result.isFinal {
                    hasResumed = true
                    let segments = self.extractSegments(from: result.bestTranscription)
                    print("SpeechRecognition: 認識完了 セグメント数=\(segments.count)")
                    continuation.resume(returning: segments)
                }
            }
        }
    }
    
    // MARK: - 分割認識
    
    /// 長い音声を分割して認識する
    private func recognizeInChunks(audioURL: URL, totalDuration: TimeInterval, recognizer: SFSpeechRecognizer) async throws -> [RecognitionSegment] {
        print("SpeechRecognition: 分割認識開始 (totalDuration=\(String(format: "%.1f", totalDuration))秒)")
        
        var allSegments: [RecognitionSegment] = []
        var chunkStart: TimeInterval = 0
        var chunkIndex = 0
        
        while chunkStart < totalDuration {
            let chunkEnd = min(chunkStart + maxChunkDuration, totalDuration)
            print("SpeechRecognition: チャンク[\(chunkIndex)] \(String(format: "%.1f", chunkStart))s - \(String(format: "%.1f", chunkEnd))s")
            
            // チャンクを書き出し
            do {
                let chunkURL = try await exportChunk(from: audioURL, start: chunkStart, end: chunkEnd, index: chunkIndex)
                
                // チャンクを認識
                let chunkSegments = try await recognizeSingle(audioURL: chunkURL, recognizer: recognizer)
                
                // タイムスタンプをオフセット
                let offsetSegments = chunkSegments.map { seg in
                    RecognitionSegment(
                        text: seg.text,
                        startTime: seg.startTime + chunkStart,
                        endTime: seg.endTime + chunkStart,
                        confidence: seg.confidence,
                        isJapanese: seg.isJapanese,
                        wordTimings: seg.wordTimings
                    )
                }
                allSegments.append(contentsOf: offsetSegments)
                
                // 一時ファイル削除
                try? FileManager.default.removeItem(at: chunkURL)
                
            } catch {
                print("SpeechRecognition: チャンク[\(chunkIndex)]認識失敗: \(error.localizedDescription)")
                // 1つのチャンクが失敗しても続行
            }
            
            chunkStart = chunkEnd
            chunkIndex += 1
            
            // リクエストの間に少し待機（レートリミット回避）
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        
        print("SpeechRecognition: 分割認識完了 合計セグメント数=\(allSegments.count)")
        
        if allSegments.isEmpty {
            throw RecognitionError.recognitionFailed("音声の認識結果が空でした。音声に日本語が含まれているか確認してください。")
        }
        
        return allSegments
    }
    
    /// 音声ファイルの一部を書き出す
    private func exportChunk(from sourceURL: URL, start: TimeInterval, end: TimeInterval, index: Int) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw RecognitionError.audioLoadFailed
        }
        
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let outputURL = documentsURL.appendingPathComponent("chunk_\(index)_\(UUID().uuidString).m4a")
        
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        
        let startTime = CMTime(seconds: start, preferredTimescale: 600)
        let endTime = CMTime(seconds: end, preferredTimescale: 600)
        exportSession.timeRange = CMTimeRange(start: startTime, end: endTime)
        
        try await exportSession.export(to: outputURL, as: .m4a)
        return outputURL
    }
    
    // MARK: - セグメント抽出
    
    private func extractSegments(from transcription: SFTranscription) -> [RecognitionSegment] {
        let sfSegments = transcription.segments
        guard !sfSegments.isEmpty else { return [] }
        
        var result: [RecognitionSegment] = []
        var currentText = ""
        var currentStart: TimeInterval = sfSegments[0].timestamp
        var currentEnd: TimeInterval = sfSegments[0].timestamp + sfSegments[0].duration
        var totalConfidence: Float = 0
        var wordCount: Int = 0
        
        let sentenceEnders: Set<Character> = ["。", "、", "！", "？", ".", "!", "?", "\n"]
        
        for sfSegment in sfSegments {
            currentText += sfSegment.substring
            currentEnd = sfSegment.timestamp + sfSegment.duration
            totalConfidence += sfSegment.confidence
            wordCount += 1
            
            let lastChar = sfSegment.substring.last
            let isSentenceEnd = lastChar.map { sentenceEnders.contains($0) } ?? false
            let isLongEnough = currentText.count >= 30
            
            if isSentenceEnd || isLongEnough {
                let segment = RecognitionSegment(
                    text: currentText.trimmingCharacters(in: .whitespaces),
                    startTime: currentStart,
                    endTime: currentEnd,
                    confidence: wordCount > 0 ? totalConfidence / Float(wordCount) : 0,
                    isJapanese: true,
                    wordTimings: nil
                )
                if !segment.text.isEmpty {
                    result.append(segment)
                }
                currentText = ""
                currentStart = currentEnd
                totalConfidence = 0
                wordCount = 0
            }
        }
        
        if !currentText.trimmingCharacters(in: .whitespaces).isEmpty {
            result.append(RecognitionSegment(
                text: currentText.trimmingCharacters(in: .whitespaces),
                startTime: currentStart,
                endTime: currentEnd,
                confidence: wordCount > 0 ? totalConfidence / Float(wordCount) : 0,
                isJapanese: true,
                wordTimings: nil
            ))
        }
        
        return result
    }
}

// MARK: - Mock実装

final class MockSpeechRecognitionService: SpeechRecognitionServiceProtocol {
    
    func requestAuthorization() async -> Bool { true }
    
    func recognize(audioURL: URL, preferredLanguageCode: String?) async throws -> [RecognitionSegment] {
        _ = preferredLanguageCode
        try await Task.sleep(nanoseconds: 2_000_000_000)
        return [
            RecognitionSegment(text: "皆さん、こんにちは。", startTime: 0.0, endTime: 2.5, confidence: 0.95),
            RecognitionSegment(text: "今日は日本語の勉強について話しましょう。", startTime: 2.5, endTime: 6.0, confidence: 0.92),
        ]
    }
}

// MARK: - エラー定義

enum RecognitionError: Error, LocalizedError {
    case notAvailable
    case notAuthorized
    case recognitionFailed(String)
    case audioLoadFailed
    
    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "音声認識が利用できません。デバイスの設定を確認してください。"
        case .notAuthorized:
            return "音声認識の権限がありません。設定アプリから音声認識を許可してください。"
        case .recognitionFailed(let message):
            return "音声認識に失敗しました: \(message)"
        case .audioLoadFailed:
            return "音声ファイルの読み込みに失敗しました"
        }
    }
}
