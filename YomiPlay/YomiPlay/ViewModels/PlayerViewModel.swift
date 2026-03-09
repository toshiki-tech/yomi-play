//
//  PlayerViewModel.swift
//  YomiPlay
//
//  プレーヤー画面のViewModel
//  再生制御・字幕同期・設定・字幕編集を管理する
//

import Foundation
import AVFoundation
import Translation

// MARK: - プレーヤー画面ViewModel

@Observable
final class PlayerViewModel {
    
    // MARK: - 公開プロパティ
    
    var document: TranscriptDocument
    var playerService: AudioPlayerService
    
    // 表示設定（UserDefaults で永続化）
    var showFurigana: Bool = true { didSet { Self.defaults.set(showFurigana, forKey: "showFurigana") } }
    var showRomaji: Bool = true { didSet { Self.defaults.set(showRomaji, forKey: "showRomaji") } }
    var showEnglish: Bool = true { didSet { Self.defaults.set(showEnglish, forKey: "showEnglish") } }
    var fontSize: CGFloat = 18 { didSet { Self.defaults.set(fontSize, forKey: "fontSize") } }
    var isLooping: Bool = false
    
    // 翻訳設定（UserDefaults で永続化）
    var targetLanguageCode: String = "zh-Hans" { didSet { Self.defaults.set(targetLanguageCode, forKey: "targetLanguageCode") } }
    var showTranslation: Bool = false { didSet { Self.defaults.set(showTranslation, forKey: "showTranslation") } }
    
    // 再生速度（UserDefaults で永続化）
    var playbackRate: Float = 1.0 { didSet { Self.defaults.set(playbackRate, forKey: "playbackRate") } }
    static let availableRates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
    
    private static let defaults = UserDefaults.standard
    
    // 字幕編集
    var editingSegmentID: UUID? = nil
    var editingText: String = ""
    var editingSkipFurigana: Bool = false
    
    private let furiganaService = CFStringTokenizerFuriganaService()
    private let translationService = TranslationService.shared
    
    /// 翻訳中かどうか
    var isTranslating: Bool = false
    
    // MARK: - 初期化
    
    init(document: TranscriptDocument) {
        self.document = document
        self.playerService = AudioPlayerService()
        
        restoreSettings()
        
        if let url = document.source.playbackURL {
            playerService.loadAudio(from: url)
        }
        playerService.setSegments(document.segments)
        playerService.setPlaybackRate(playbackRate)
        
        regenerateFuriganaIfNeeded()
    }
    
    /// UserDefaults から保存済みの設定を復元する
    private func restoreSettings() {
        let d = Self.defaults
        
        if d.object(forKey: "showFurigana") != nil {
            showFurigana = d.bool(forKey: "showFurigana")
        }
        if d.object(forKey: "showRomaji") != nil {
            showRomaji = d.bool(forKey: "showRomaji")
        }
        if d.object(forKey: "showEnglish") != nil {
            showEnglish = d.bool(forKey: "showEnglish")
        }
        if d.object(forKey: "showTranslation") != nil {
            showTranslation = d.bool(forKey: "showTranslation")
        }
        if d.object(forKey: "fontSize") != nil {
            let stored = d.double(forKey: "fontSize")
            if stored >= 12 && stored <= 32 { fontSize = stored }
        }
        if d.object(forKey: "playbackRate") != nil {
            let stored = d.float(forKey: "playbackRate")
            if Self.availableRates.contains(stored) { playbackRate = stored }
        }
        
        if let stored = d.string(forKey: "targetLanguageCode"), !stored.isEmpty {
            targetLanguageCode = stored
        } else {
            targetLanguageCode = Self.detectDefaultLanguageCode()
        }
    }
    
    /// システム言語から翻訳先のデフォルト言語コードを推定する
    private static func detectDefaultLanguageCode() -> String {
        let preferred = Locale.preferredLanguages.first ?? "en"
        if preferred.hasPrefix("zh-Hans") || preferred.hasPrefix("zh-CN") { return "zh-Hans" }
        if preferred.hasPrefix("zh-Hant") || preferred.hasPrefix("zh-TW") || preferred.hasPrefix("zh-HK") { return "zh-Hant" }
        if preferred.hasPrefix("en") { return "en" }
        return "zh-Hans"
    }
    
    /// 保存済みドキュメントの tokens に isKatakana / englishMeaning が入っていない場合、
    /// 全セグメントの振り仮名を再生成して最新の辞書データを反映する
    private func regenerateFuriganaIfNeeded() {
        let needsRegeneration = document.segments.contains { segment in
            !segment.skipFurigana &&
            !segment.originalText.isEmpty &&
            segment.tokens.contains { token in
                CFStringTokenizerFuriganaService.isKatakanaWord(token.surface) && token.englishMeaning == nil
            }
        }
        guard needsRegeneration else { return }
        
        Task {
            var updated = document.segments
            for i in updated.indices where !updated[i].skipFurigana {
                let newTokens = await furiganaService.generateFurigana(for: updated[i].originalText)
                updated[i].tokens = newTokens
            }
            await MainActor.run {
                document.segments = updated
                playerService.setSegments(document.segments)
                saveDocument()
                print("PlayerViewModel: 振り仮名を再生成しました（外来語辞書反映）")
            }
        }
    }
    
    // MARK: - 再生コントロール
    
    func togglePlayPause() {
        playerService.togglePlayPause()
    }
    
    func skipBackward() {
        playerService.skip(seconds: -5)
    }
    
    func skipForward() {
        playerService.skip(seconds: 10)
    }
    
    func seek(to time: TimeInterval) {
        playerService.seek(to: time)
    }
    
    // MARK: - 再生速度
    
    func cyclePlaybackRate() {
        guard let currentIndex = Self.availableRates.firstIndex(of: playbackRate) else {
            playbackRate = 1.0
            playerService.setPlaybackRate(1.0)
            return
        }
        let nextIndex = (currentIndex + 1) % Self.availableRates.count
        playbackRate = Self.availableRates[nextIndex]
        playerService.setPlaybackRate(playbackRate)
    }
    
    var playbackRateText: String {
        if playbackRate == 1.0 { return "1x" }
        if playbackRate == floor(playbackRate) { return "\(Int(playbackRate))x" }
        return String(format: "%.2gx", playbackRate)
    }
    
    // MARK: - 字幕操作
    
    func onSegmentTapped(_ segment: TranscriptSegment) {
        playerService.seek(to: segment.startTime)
        if !playerService.isPlaying {
            playerService.play()
        }
    }
    
    func toggleCurrentLoop() {
        if isLooping {
            isLooping = false
            playerService.setLoopSegment(nil)
        } else if let segmentID = playerService.currentSegmentID,
                  let segment = document.segments.first(where: { $0.id == segmentID }) {
            isLooping = true
            playerService.setLoopSegment(segment)
        }
    }
    
    // MARK: - 字幕編集
    
    /// 編集を開始する
    func startEditing(segment: TranscriptSegment) {
        editingSegmentID = segment.id
        editingText = segment.originalText
        editingSkipFurigana = segment.skipFurigana
    }
    
    /// 編集をキャンセルする
    func cancelEditing() {
        editingSegmentID = nil
        editingText = ""
        editingSkipFurigana = false
    }
    
    /// 編集を確定し、振り仮名を再生成する
    func confirmEditing() {
        guard let segmentID = editingSegmentID,
              let index = document.segments.firstIndex(where: { $0.id == segmentID }) else {
            cancelEditing()
            return
        }
        
        let newText = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newText.isEmpty else {
            cancelEditing()
            return
        }
        
        let shouldSkip = editingSkipFurigana
        let segmentIndex = index
        
        Task {
            let tokens: [FuriganaToken] = shouldSkip
                ? []
                : await furiganaService.generateFurigana(for: newText)
            
            await MainActor.run {
                document.segments[segmentIndex].originalText = newText
                document.segments[segmentIndex].tokens = tokens
                document.segments[segmentIndex].skipFurigana = shouldSkip
                // テキストが変わったので翻訳は一旦破棄する
                document.segments[segmentIndex].translatedText = nil
                
                playerService.setSegments(document.segments)
                saveDocument()
                
                editingSegmentID = nil
                editingText = ""
                editingSkipFurigana = false
            }
        }
    }
    
    // MARK: - 字幕翻訳
    
    /// 翻訳を開始するためのトリガー（SwiftUI .translationTask で監視）
    var translationConfiguration: TranslationSession.Configuration?
    
    /// 翻訳ボタンを押したとき：Configuration を設定して .translationTask を発火させる
    func requestTranslation() {
        translationConfiguration = nil
        isTranslating = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [self] in
            translationConfiguration = translationService.makeConfiguration(
                sourceLanguageCode: "ja",
                targetLanguageCode: targetLanguageCode
            )
        }
    }
    
    /// .translationTask のコールバックで呼ばれる
    @MainActor
    func performTranslation(using session: TranslationSession) async {
        let segments = document.segments
        guard !segments.isEmpty else {
            isTranslating = false
            return
        }
        
        let requests = segments.enumerated().map { index, seg in
            TranslationSession.Request(
                sourceText: seg.originalText,
                clientIdentifier: "\(index)"
            )
        }
        
        do {
            let responses = try await session.translations(from: requests)
            for response in responses {
                if let idStr = response.clientIdentifier,
                   let idx = Int(idStr),
                   idx < document.segments.count {
                    document.segments[idx].translatedText = response.targetText
                }
            }
            saveDocument()
            showTranslation = true
        } catch {
            print("PlayerViewModel: 翻訳失敗 - \(error)")
        }
        isTranslating = false
    }
    
    /// ドキュメントを保存する
    func saveDocument() {
        do {
            try DocumentStore.shared.save(document)
            print("PlayerViewModel: ドキュメント保存完了")
        } catch {
            print("PlayerViewModel: 保存失敗: \(error)")
        }
    }
    
    /// 現在の再生位置をドキュメントに保存する（画面を出るときに呼ぶ）
    func savePlaybackPosition() {
        document.lastPlaybackPosition = playerService.currentTime
        saveDocument()
    }
    
    // MARK: - 設定
    
    func adjustFontSize(by delta: CGFloat) {
        fontSize = max(12, min(32, fontSize + delta))
    }
    
    // MARK: - ヘルパー
    
    var isPlaying: Bool { playerService.isPlaying }
    
    var progress: Double {
        guard playerService.duration > 0 else { return 0 }
        return playerService.currentTime / playerService.duration
    }
}
