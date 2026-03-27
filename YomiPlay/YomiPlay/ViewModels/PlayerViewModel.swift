//
//  PlayerViewModel.swift
//  YomiPlay
//
//  プレーヤー画面のViewModel
//  再生制御・字幕同期・設定・字幕編集を管理する
//

import Foundation
import AVFoundation

// MARK: - 再生リピートモード（整段 / 单句）

enum PlaybackRepeatMode: String, CaseIterable, Identifiable {
    case off
    case wholeTrack
    case currentSubtitle
    
    var id: String { rawValue }
}

// MARK: - プレーヤー画面ViewModel

@MainActor
@Observable
final class PlayerViewModel {
    
    // MARK: - 公開プロパティ
    
    var document: TranscriptDocument
    var playerService: AudioPlayerService
    
    // 表示設定（UserDefaults で永続化）。初始化应用「非日语识别源」默认关假名时暂不写入，避免覆盖日语内容的用户偏好
    private var persistDisplayToggles = true
    var showFurigana: Bool = true {
        didSet { if persistDisplayToggles { Self.defaults.set(showFurigana, forKey: "showFurigana") } }
    }
    var showRomaji: Bool = true {
        didSet { if persistDisplayToggles { Self.defaults.set(showRomaji, forKey: "showRomaji") } }
    }
    var showEnglish: Bool = true {
        didSet { if persistDisplayToggles { Self.defaults.set(showEnglish, forKey: "showEnglish") } }
    }
    var fontSize: CGFloat = 18 { didSet { Self.defaults.set(fontSize, forKey: "fontSize") } }
    
    /// 重复播放：关闭 / 整段循环 / 当前单句循环（UserDefaults）
    var repeatMode: PlaybackRepeatMode = .off
    
    /// 下一句字幕开始前停顿秒数（跟读用，0 表示不停；单句循环时不插入）
    var interSubtitlePauseSeconds: Double = 0
    
    // 翻訳設定（UserDefaults で永続化）
    var targetLanguageCode: String = "zh-Hans" { didSet { Self.defaults.set(targetLanguageCode, forKey: "targetLanguageCode") } }
    var showTranslation: Bool = false { didSet { Self.defaults.set(showTranslation, forKey: "showTranslation") } }
    
    // 再生速度（UserDefaults で永続化）
    var playbackRate: Float = 1.0 { didSet { Self.defaults.set(playbackRate, forKey: "playbackRate") } }
    static let availableRates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
    
    private static let defaults = UserDefaults.standard
    private static let playbackRepeatModeKey = "playbackRepeatMode"
    private static let interSubtitlePauseKey = "interSubtitlePauseSeconds"
    
    /// 切到单句循环时延迟 seek 的任务；离开单句模式时必须取消，否则会与句间停顿/正常播放打架
    private var applyCurrentSubtitleSeekWorkItem: DispatchWorkItem?
    
    // 字幕編集
    var editingSegmentID: UUID? = nil
    var editingText: String = ""
    /// 编辑时本条翻译结果（确定后写回 segment.translatedText）
    var editingTranslatedText: String? = nil
    var editingSkipFurigana: Bool = false
    var editingStartTime: TimeInterval = 0
    var editingEndTime: TimeInterval = 0
    
    private let furiganaService = CFStringTokenizerFuriganaService()
    private let translationService = TranslationService.shared
    
    /// 翻訳中かどうか
    var isTranslating: Bool = false
    /// 手动翻译失败时显示
    var showTranslationError: Bool = false
    var translationErrorMessage: String?
    
    /// 元の動画ファイルの URL（動画インポート時のみ設定される）
    var videoPlaybackURL: URL? {
        document.source.videoPlaybackURL
    }
    
    // MARK: - 初期化
    
    init(document: TranscriptDocument) {
        self.document = document
        self.playerService = AudioPlayerService()
        
        persistDisplayToggles = false
        restoreSettings()
        if document.isNonJapaneseRecognitionSource == true {
            showFurigana = false
            showRomaji = false
            showEnglish = false
        }
        persistDisplayToggles = true
        // 若文档已有翻译且用户从未设置过 showTranslation，默认显示翻译
        if !showTranslation,
           Self.defaults.object(forKey: "showTranslation") == nil,
           document.segments.contains(where: { $0.translatedText != nil && !($0.translatedText ?? "").isEmpty }) {
            showTranslation = true
        }
        
        // 動画がある場合は動画ファイルをロード（映像＋音声を統一AVPlayerで管理）
        let mediaURL = document.source.videoPlaybackURL ?? document.source.playbackURL
        if let url = mediaURL {
            playerService.loadAudio(from: url)
        }
        playerService.setSegments(document.segments)
        playerService.interSubtitlePauseSeconds = interSubtitlePauseSeconds
        playerService.setPlaybackRate(playbackRate)
        syncRepeatModeWithPlayer()
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
            if stored >= 12 && stored <= 48 { fontSize = stored }
        }
        if d.object(forKey: "playbackRate") != nil {
            let stored = d.float(forKey: "playbackRate")
            if Self.availableRates.contains(stored) { playbackRate = stored }
        }
        
        if let raw = d.string(forKey: Self.playbackRepeatModeKey),
           let mode = PlaybackRepeatMode(rawValue: raw) {
            repeatMode = mode
        }
        if d.object(forKey: Self.interSubtitlePauseKey) != nil {
            let p = d.double(forKey: Self.interSubtitlePauseKey)
            interSubtitlePauseSeconds = max(0, min(6, p))
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
        if repeatMode == .currentSubtitle {
            playerService.setLoopSegment(segment)
        }
        if !playerService.isPlaying {
            playerService.play()
        }
    }
    
    /// 轻点重复按钮时按「关 → 整段 → 单句」轮换（配合菜单的长按直选）
    func cycleRepeatMode() {
        let order = PlaybackRepeatMode.allCases
        guard let i = order.firstIndex(of: repeatMode) else { return }
        let next = order[(i + 1) % order.count]
        setRepeatMode(next)
    }
    
    /// 切换 repeat 模式并持久化
    func setRepeatMode(_ mode: PlaybackRepeatMode) {
        HapticManager.shared.selection()
        if repeatMode == mode {
            return
        }
        applyCurrentSubtitleSeekWorkItem?.cancel()
        applyCurrentSubtitleSeekWorkItem = nil
        repeatMode = mode
        let key = Self.playbackRepeatModeKey
        let raw = mode.rawValue
        DispatchQueue.global(qos: .utility).async {
            UserDefaults.standard.set(raw, forKey: key)
        }
        switch mode {
        case .off, .wholeTrack:
            playerService.setLoopSegment(nil)
        case .currentSubtitle:
            syncRepeatModeWithPlayer()
            if let seg = playerService.loopingSegment {
                let shouldPlayAfterSeek = !playerService.isPlaying
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    let service = self.playerService
                    guard self.repeatMode == .currentSubtitle,
                          service.loopingSegment?.id == seg.id else { return }
                    service.seek(to: seg.startTime)
                    if shouldPlayAfterSeek {
                        service.play()
                    }
                }
                applyCurrentSubtitleSeekWorkItem = work
                DispatchQueue.main.async(execute: work)
            }
        }
    }
    
    /// 与播放器同步单句循环目标（时间轴编辑等之后调用）
    func syncRepeatModeWithPlayer() {
        switch repeatMode {
        case .off, .wholeTrack:
            playerService.setLoopSegment(nil)
        case .currentSubtitle:
            let t = playerService.currentTime
            if let id = playerService.currentSegmentID,
               let seg = document.segments.first(where: { $0.id == id }) {
                playerService.setLoopSegment(seg)
            } else if let seg = document.segments.first(where: { $0.contains(time: t) }) {
                playerService.setLoopSegment(seg)
            } else {
                playerService.setLoopSegment(nil)
            }
        }
    }
    
    /// 句间停顿时长（秒），写入默认设置并应用到播放器
    func setInterSubtitlePause(seconds: Double) {
        let c = max(0, min(6, seconds))
        interSubtitlePauseSeconds = c
        Self.defaults.set(c, forKey: Self.interSubtitlePauseKey)
        playerService.interSubtitlePauseSeconds = c
    }
    
    // MARK: - 字幕編集
    
    /// 編集を開始する
    func startEditing(segment: TranscriptSegment) {
        editingSegmentID = segment.id
        editingText = segment.originalText
        editingTranslatedText = segment.translatedText
        editingSkipFurigana = segment.skipFurigana
        editingStartTime = segment.startTime
        editingEndTime = segment.endTime
    }

    /// 編集をキャンセルする
    func cancelEditing() {
        editingSegmentID = nil
        editingText = ""
        editingTranslatedText = nil
        editingSkipFurigana = false
        editingStartTime = 0
        editingEndTime = 0
    }
    
    /// 編集を確定し、振り仮名を再生成する
    func confirmEditing() {
        guard let segmentID = editingSegmentID,
              let index = document.segments.firstIndex(where: { $0.id == segmentID }) else {
            print("PlayerViewModel: 編集対象が見つかりません id=\(String(describing: editingSegmentID))")
            cancelEditing()
            return
        }
        
        let newText = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newText.isEmpty else {
            print("PlayerViewModel: 空のテキストのため編集をキャンセルします")
            cancelEditing()
            return
        }
        
        let shouldSkip = editingSkipFurigana
        let segmentIndex = index
        let duration = playerService.duration
        let clampedStart = max(0, min(editingStartTime, duration))
        let clampedEnd = max(clampedStart, min(editingEndTime, duration > 0 ? duration : editingEndTime))
        
        print("PlayerViewModel: 編集を確定中... text=\(newText), skip=\(shouldSkip), start=\(clampedStart), end=\(clampedEnd)")
        
        Task {
            // 1. 新しい振り仮名を生成（非メインスレッド）
            let tokens: [FuriganaToken] = shouldSkip
                ? []
                : await furiganaService.generateFurigana(for: newText)
            
            // 2. メインスレッドでドキュメントを更新して保存
            await MainActor.run {
                // インデックスガード
                guard segmentIndex < self.document.segments.count else { return }
                
                // プロパティを個別に更新
                self.document.segments[segmentIndex].startTime = clampedStart
                self.document.segments[segmentIndex].endTime = clampedEnd
                self.document.segments[segmentIndex].originalText = newText
                self.document.segments[segmentIndex].tokens = tokens
                self.document.segments[segmentIndex].skipFurigana = shouldSkip
                self.document.segments[segmentIndex].translatedText = self.editingTranslatedText
                self.editingTranslatedText = nil
                
                // 再生サービス側も同期
                self.playerService.setSegments(self.document.segments)
                self.syncRepeatModeWithPlayer()
                
                // 編集状態リセット
                self.editingSegmentID = nil
                self.editingText = ""
                self.editingSkipFurigana = false
                self.editingStartTime = 0
                self.editingEndTime = 0
                
                // 即座に保存
                self.saveDocument()
                print("PlayerViewModel: 編集内容を適用して保存しました id=\(segmentID)")
            }
        }
    }
    
    /// 現在編集中の字幕を削除する
    func deleteCurrentSegment() {
        guard let segmentID = editingSegmentID,
              let index = document.segments.firstIndex(where: { $0.id == segmentID }) else {
            return
        }
        document.segments.remove(at: index)
        playerService.setSegments(document.segments)
        syncRepeatModeWithPlayer()
        cancelEditing()
        saveDocument()
        print("PlayerViewModel: セグメントを削除しました id=\(segmentID)")
    }
    
    /// 現在の再生位置で字幕を二つに分割する
    func splitCurrentSegmentAtCurrentTime() {
        guard let segmentID = editingSegmentID,
              let index = document.segments.firstIndex(where: { $0.id == segmentID }) else {
            return
        }
        let segment = document.segments[index]
        let t = playerService.currentTime
        guard t > segment.startTime, t < segment.endTime else {
            print("PlayerViewModel: 分割位置がセグメント範囲外のため処理しません")
            return
        }
        
        let first = TranscriptSegment(
            id: segment.id,
            startTime: segment.startTime,
            endTime: t,
            originalText: segment.originalText,
            tokens: segment.tokens,
            confidence: segment.confidence,
            skipFurigana: segment.skipFurigana,
            translatedText: segment.translatedText
        )
        let second = TranscriptSegment(
            startTime: t,
            endTime: segment.endTime,
            originalText: segment.originalText,
            tokens: segment.tokens,
            confidence: segment.confidence,
            skipFurigana: segment.skipFurigana,
            translatedText: segment.translatedText
        )
        
        document.segments.remove(at: index)
        document.segments.insert(contentsOf: [first, second], at: index)
        playerService.setSegments(document.segments)
        syncRepeatModeWithPlayer()
        
        // 新しい後半セグメントを編集中として扱う
        editingSegmentID = second.id
        editingStartTime = second.startTime
        editingEndTime = second.endTime
        editingText = second.originalText
        editingSkipFurigana = second.skipFurigana
        
        saveDocument()
        print("PlayerViewModel: セグメントを分割しました id=\(segmentID) at t=\(t)")
    }
    
    /// 現在編集中の字幕を前の字幕と結合する
    func mergeCurrentWithPrevious() {
        guard let segmentID = editingSegmentID,
              let index = document.segments.firstIndex(where: { $0.id == segmentID }),
              index > 0 else {
            return
        }
        
        let prev = document.segments[index - 1]
        let current = document.segments[index]
        
        let mergedStart = min(prev.startTime, current.startTime)
        let mergedEnd = max(prev.endTime, current.endTime)
        let mergedText = (prev.originalText + " " + current.originalText).trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldSkip = prev.skipFurigana && current.skipFurigana
        let targetIndex = index - 1
        
        Task {
            let tokens: [FuriganaToken] = shouldSkip
                ? []
                : await furiganaService.generateFurigana(for: mergedText)
            
            await MainActor.run {
                guard targetIndex < self.document.segments.count else { return }
                self.document.segments[targetIndex].startTime = mergedStart
                self.document.segments[targetIndex].endTime = mergedEnd
                self.document.segments[targetIndex].originalText = mergedText
                self.document.segments[targetIndex].tokens = tokens
                self.document.segments[targetIndex].skipFurigana = shouldSkip
                self.document.segments[targetIndex].translatedText = nil
                
                // 現在のセグメントを削除
                if index < self.document.segments.count {
                    self.document.segments.remove(at: index)
                }
                
                self.playerService.setSegments(self.document.segments)
                self.syncRepeatModeWithPlayer()
                
                // 結合後のセグメントを編集中として扱う
                self.editingSegmentID = self.document.segments[targetIndex].id
                self.editingStartTime = mergedStart
                self.editingEndTime = mergedEnd
                self.editingText = mergedText
                self.editingSkipFurigana = shouldSkip
                
                self.saveDocument()
                print("PlayerViewModel: セグメントを結合しました prev=\(prev.id), current=\(segmentID)")
            }
        }
    }
    
    // MARK: - 字幕翻訳（仅对现有字幕文本做翻译，不涉及语音识别）

    /// 翻译全部字幕：对当前每条字幕的 originalText 调用系统翻译，结果写入 translatedText
    @MainActor
    func translateAllSegments() async {
        let segments = document.segments
        guard !segments.isEmpty else { return }
        isTranslating = true
        defer { isTranslating = false }
        do {
            let result = try await translationService.translateSegments(
                segments,
                sourceLanguageCode: "ja",
                targetLanguageCode: targetLanguageCode
            )
            document.segments = result
            playerService.setSegments(document.segments)
            syncRepeatModeWithPlayer()
            saveDocument()
            showTranslation = true
        } catch {
            print("PlayerViewModel: 翻译全部失败 - \(error)")
            translationErrorMessage = (error as? TranslationServiceError) == .notAvailable
                ? String(localized: "translation_requires_newer_ios")
                : error.localizedDescription
            showTranslationError = true
        }
    }

    /// 编辑时翻译当前这条字幕（使用当前编辑框文本与设置中的目标语言）
    @MainActor
    func translateCurrentSegment() async {
        let text = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let targetLang = targetLanguageCode
        isTranslating = true
        defer { isTranslating = false }
        do {
            let translated = try await translationService.translateText(text, targetLanguageCode: targetLang)
            editingTranslatedText = translated.isEmpty ? nil : translated
        } catch {
            print("PlayerViewModel: 单条翻译失败 - \(error)")
            translationErrorMessage = (error as? TranslationServiceError) == .notAvailable
                ? String(localized: "translation_requires_newer_ios")
                : error.localizedDescription
            showTranslationError = true
        }
    }

    // MARK: - SRT インポート
    
    var isImportingSRT: Bool = false
    var showSRTImportSuccess: Bool = false
    
    /// SRT ファイルをインポートして現在の字幕を置き換える
    func importSRT(from url: URL) {
        isImportingSRT = true
        Task {
            do {
                let srtSegments = try SubtitleImportService.parseSRT(from: url)
                guard !srtSegments.isEmpty else {
                    await MainActor.run { isImportingSRT = false }
                    return
                }
                
                var transcriptSegments: [TranscriptSegment] = []
                for seg in srtSegments {
                    let tokens = await furiganaService.generateFurigana(for: seg.text)
                    transcriptSegments.append(TranscriptSegment(
                        startTime: seg.startTime,
                        endTime: seg.endTime,
                        originalText: seg.text,
                        tokens: tokens
                    ))
                }
                
                await MainActor.run {
                    document.segments = transcriptSegments
                    playerService.setSegments(document.segments)
                    syncRepeatModeWithPlayer()
                    saveDocument()
                    isImportingSRT = false
                    showSRTImportSuccess = true
                    print("PlayerViewModel: SRT インポート完了 \(transcriptSegments.count) セグメント")
                }
            } catch {
                await MainActor.run {
                    isImportingSRT = false
                    print("PlayerViewModel: SRT インポート失敗: \(error)")
                }
            }
        }
    }
    
    // MARK: - .yomi インポート
    
    var isImportingYomi: Bool = false
    var showYomiImportSuccess: Bool = false
    
    /// .yomi ファイルをインポートして現在の字幕を置き換える
    func importYomi(from url: URL) {
        isImportingYomi = true
        Task {
            do {
                let importedDoc = try SubtitleExportService.readYomiFile(from: url)
                await MainActor.run {
                    document.segments = importedDoc.segments
                    playerService.setSegments(document.segments)
                    syncRepeatModeWithPlayer()
                    saveDocument()
                    isImportingYomi = false
                    showYomiImportSuccess = true
                    print("PlayerViewModel: .yomi インポート完了 \(importedDoc.segments.count) セグメント")
                }
            } catch {
                await MainActor.run {
                    isImportingYomi = false
                    print("PlayerViewModel: .yomi インポート失敗: \(error)")
                }
            }
        }
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
        fontSize = max(12, min(48, fontSize + delta))
    }
    
    // MARK: - ヘルパー
    
    var isPlaying: Bool { playerService.isPlaying }
    
    var progress: Double {
        guard playerService.duration > 0 else { return 0 }
        return playerService.currentTime / playerService.duration
    }
}
