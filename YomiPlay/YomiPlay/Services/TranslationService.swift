//
//  TranslationService.swift
//  YomiPlay
//
//  Apple Translation フレームワークを使った字幕翻訳サービス
//  Translation は iOS 26.0 以上で利用可能（SDK による）。それ未満では notAvailable を返す。
//

import Foundation
import Translation

enum TranslationServiceError: Error {
    case notAvailable
}

/// 字幕セグメント配列をまとめて翻訳するサービス
final class TranslationService {
    
    static let shared = TranslationService()
    
    private init() {}
    
    /// セグメント配列を targetLanguageCode で指定された言語に翻訳する
    /// - Parameters:
    ///   - segments: 翻訳対象のセグメント配列
    ///   - sourceLanguageCode: 元の言語コード（デフォルトは日本語 "ja"）
    ///   - targetLanguageCode: 翻訳先の言語コード（例: "zh-Hans", "en"）
    /// - Returns: translatedText が埋め込まれた新しいセグメント配列
    func translateSegments(
        _ segments: [TranscriptSegment],
        sourceLanguageCode: String = "ja",
        targetLanguageCode: String
    ) async throws -> [TranscriptSegment] {
        guard !segments.isEmpty else { return segments }
        
        guard #available(iOS 26.0, *) else {
            throw TranslationServiceError.notAvailable
        }
        
        return try await translateSegmentsWithFramework(
            segments,
            sourceLanguageCode: sourceLanguageCode,
            targetLanguageCode: targetLanguageCode
        )
    }
    
    @available(iOS 26.0, *)
    private func translateSegmentsWithFramework(
        _ segments: [TranscriptSegment],
        sourceLanguageCode: String,
        targetLanguageCode: String
    ) async throws -> [TranscriptSegment] {
        let source = Locale.Language(identifier: sourceLanguageCode)
        let target = Locale.Language(identifier: targetLanguageCode)
        
        let session = TranslationSession(installedSource: source, target: target)
        
        let requests = segments.enumerated().map { index, seg in
            TranslationSession.Request(
                sourceText: seg.originalText,
                clientIdentifier: "\(index)"
            )
        }
        
        let responses = try await session.translations(from: requests)
        
        var result = segments
        for response in responses {
            if let idStr = response.clientIdentifier,
               let idx = Int(idStr),
               idx < result.count {
                result[idx].translatedText = response.targetText
            }
        }
        return result
    }

    /// 单句翻译（用于编辑时「翻译这条」）
    func translateText(
        _ text: String,
        sourceLanguageCode: String = "ja",
        targetLanguageCode: String
    ) async throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        let segment = TranscriptSegment(startTime: 0, endTime: 0, originalText: text)
        let result = try await translateSegments([segment], sourceLanguageCode: sourceLanguageCode, targetLanguageCode: targetLanguageCode)
        return result.first?.translatedText ?? ""
    }

    /// 翻訳用の Configuration を作成する（SwiftUI の .translationTask で使用）。iOS 26.0 以上のみ。
    @available(iOS 26.0, *)
    func makeConfiguration(
        sourceLanguageCode: String = "ja",
        targetLanguageCode: String
    ) -> TranslationSession.Configuration {
        TranslationSession.Configuration(
            source: Locale.Language(identifier: sourceLanguageCode),
            target: Locale.Language(identifier: targetLanguageCode)
        )
    }
}

