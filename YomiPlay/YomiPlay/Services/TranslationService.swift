//
//  TranslationService.swift
//  YomiPlay
//
//  Apple Translation フレームワークを使った字幕翻訳サービス
//  Translation は iOS 26.0 以上で利用可能。未満では notAvailable を返す。
//

import Foundation
import Translation

enum TranslationServiceError: Error {
    case notAvailable
}

/// 字幕セグメント配列をまとめて翻訳するサービス
final class TranslationService {
    
    static let shared = TranslationService()
    static var isAvailableOnCurrentSystem: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }
    
    private init() {}
    
    /// セグメント配列を targetLanguageCode で指定された言語に翻訳する。
    /// 各句の源语言来自 `originalTextLanguageCode`（及可选的文档级「非日语识别源」回退）；源与目标相同时不写系统翻译，直接复制原文。
    func translateSegments(
        _ segments: [TranscriptSegment],
        targetLanguageCode: String,
        documentNonJapaneseRecognitionSource: Bool? = nil
    ) async throws -> [TranscriptSegment] {
        guard !segments.isEmpty else { return segments }
        
        guard #available(iOS 26.0, *) else {
            throw TranslationServiceError.notAvailable
        }
        
        let targetNorm = TranslationTargetLanguageOptions.normalizedCode(targetLanguageCode)
        var result = segments
        
        var groups: [String: [Int]] = [:]
        
        for i in result.indices {
            let rawText = result[i].originalText.trimmingCharacters(in: .whitespacesAndNewlines)
            if rawText.isEmpty {
                result[i].translatedText = nil
                continue
            }
            let srcId = TranslationLanguageRouting.sourceLanguageIdentifierForTranslation(
                originalTextLanguageCode: result[i].originalTextLanguageCode,
                documentNonJapaneseRecognitionSource: documentNonJapaneseRecognitionSource
            )
            if TranslationLanguageRouting.shouldSkipTranslationBecauseSameLanguage(sourceIdentifier: srcId, targetLanguageCode: targetNorm) {
                result[i].translatedText = result[i].originalText
                continue
            }
            groups[srcId, default: []].append(i)
        }
        
        for (sourceId, idxs) in groups {
            let batch = idxs.map { result[$0] }
            let translated = try await translateSegmentsWithFramework(
                batch,
                sourceLanguageCode: sourceId,
                targetLanguageCode: targetNorm
            )
            for (k, globalIdx) in idxs.enumerated() where k < translated.count {
                result[globalIdx].translatedText = translated[k].translatedText
            }
        }
        
        return result
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
        
        var batchResult = segments
        for response in responses {
            if let idStr = response.clientIdentifier,
               let idx = Int(idStr),
               idx < batchResult.count {
                batchResult[idx].translatedText = response.targetText
            }
        }
        return batchResult
    }

    /// 单句翻译（用于编辑时「翻译这条」）。`segmentSourceLanguageCode` 为 nil 时仅用文档级回退（与批量翻译一致）。
    func translateText(
        _ text: String,
        segmentSourceLanguageCode: String?,
        targetLanguageCode: String,
        documentNonJapaneseRecognitionSource: Bool? = nil
    ) async throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        let segment = TranscriptSegment(
            startTime: 0,
            endTime: 0,
            originalText: text,
            userTokenOverrides: nil,
            originalTextLanguageCode: segmentSourceLanguageCode
        )
        let out = try await translateSegments(
            [segment],
            targetLanguageCode: targetLanguageCode,
            documentNonJapaneseRecognitionSource: documentNonJapaneseRecognitionSource
        )
        return out.first?.translatedText ?? ""
    }

    /// 翻訳用の Configuration を作成する（SwiftUI の .translationTask で使用）。iOS 26.0 以上のみ。
    @available(iOS 26.0, *)
    func makeConfiguration(
        sourceLanguageCode: String,
        targetLanguageCode: String
    ) -> TranslationSession.Configuration {
        let src = TranslationLanguageRouting.normalizeCodeForAppleTranslationSession(sourceLanguageCode)
        let tgt = TranslationTargetLanguageOptions.normalizedCode(targetLanguageCode)
        return TranslationSession.Configuration(
            source: Locale.Language(identifier: src),
            target: Locale.Language(identifier: tgt)
        )
    }
}
