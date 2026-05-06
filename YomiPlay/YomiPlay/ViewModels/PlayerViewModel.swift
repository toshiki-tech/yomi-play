//
//  PlayerViewModel.swift
//  YomiPlay
//
//  プレーヤー画面のViewModel
//  再生制御・字幕同期・設定・字幕編集を管理する
//

import Foundation
import AVFoundation

// MARK: - 再生リピートモード（不循环 / 单句 / 单篇 / 列表）

enum PlaybackRepeatMode: String, CaseIterable, Identifiable {
    case off
    case currentSubtitle
    case wholeTrack
    case playlist
    
    var id: String { rawValue }
}

/// 编辑态下的逐词注音项（用于将分词 surface 与可编辑 reading 绑定）
struct EditableTokenReading: Identifiable, Equatable {
    let id: UUID
    let surface: String
    var reading: String
    var romaji: String
    /// 片假名外来词标记与英译注释，编辑后需要保留用于展示。
    var isKatakana: Bool = false
    var englishMeaning: String? = nil
    /// 保留逐词时间与词性，避免仅修改注音后丢失卡拉OK高亮与词性下划线。
    var startTime: TimeInterval? = nil
    var endTime: TimeInterval? = nil
    var partOfSpeech: PartOfSpeech? = nil
    /// 是否启用该词的英文释义编辑与保存。
    var englishMeaningEnabled: Bool = false
}

// MARK: - プレーヤー画面ViewModel

@MainActor
@Observable
final class PlayerViewModel {
    private static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "avi", "mkv", "webm"]
    
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
    
    /// 重复播放：不循环 / 单句 / 单篇 / 列表（UserDefaults）
    var repeatMode: PlaybackRepeatMode = .off
    
    /// 下一句字幕开始前停顿秒数（跟读用，0 表示不停；单句循环时不插入）
    var interSubtitlePauseSeconds: Double = 0
    
    // 翻訳設定（UserDefaults で永続化）
    var targetLanguageCode: String = "en" { didSet { Self.defaults.set(targetLanguageCode, forKey: "targetLanguageCode") } }
    var showTranslation: Bool = false { didSet { Self.defaults.set(showTranslation, forKey: "showTranslation") } }
    /// 字幕行右侧跟读麦克风入口（默认关闭，按需开启）
    var showShadowReadingMic: Bool = false {
        didSet { Self.defaults.set(showShadowReadingMic, forKey: "showShadowReadingMicInPlayer") }
    }
    
    // 再生速度（UserDefaults で永続化）
    var playbackRate: Float = 1.0 { didSet { Self.defaults.set(playbackRate, forKey: "playbackRate") } }
    static let availableRates: [Float] = [0.5, 0.75, 0.8, 0.9, 1.0, 1.25, 1.5, 2.0]
    
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
    /// 编辑时逐词注音（用于用户自定义分词注音覆盖）
    var editingTokenReadings: [EditableTokenReading] = []
    /// 注音编辑页的手动分词文本（以 `|` 分隔）
    var editingTokenSegmentationText: String = ""
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
    /// 目标语言首次可能需要下载语言包时的提示
    var showTranslationNetworkHint: Bool = false
    private static let translationPackReadyCodesKey = "translationPackReadyCodes"
    private static let translationPackHintShownCodesKey = "translationPackHintShownCodes"
    
    /// 元の動画ファイルの URL（動画インポート時のみ設定される）
    var videoPlaybackURL: URL? {
        if let videoURL = document.source.videoPlaybackURL {
            return videoURL
        }
        guard let playback = document.source.playbackURL else { return nil }
        let ext = playback.pathExtension.lowercased()
        return Self.videoExtensions.contains(ext) ? playback : nil
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
        let mediaURL = videoPlaybackURL ?? document.source.playbackURL
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
        if d.object(forKey: "showShadowReadingMicInPlayer") != nil {
            showShadowReadingMic = d.bool(forKey: "showShadowReadingMicInPlayer")
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
            targetLanguageCode = TranslationTargetLanguageOptions.normalizedCode(stored)
        } else {
            targetLanguageCode = TranslationTargetLanguageOptions.defaultTargetCode()
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

    func setPlaybackRate(_ rate: Float) {
        guard Self.availableRates.contains(rate) else { return }
        if playbackRate == rate { return }
        playbackRate = rate
        playerService.setPlaybackRate(rate)
        HapticManager.shared.selection()
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
    
    /// 轻点重复按钮时按「不循环 → 单句 → 单篇 → 列表」轮换（配合菜单的长按直选）
    func cycleRepeatMode() {
        let order: [PlaybackRepeatMode] = [.off, .currentSubtitle, .wholeTrack, .playlist]
        guard let i = order.firstIndex(of: repeatMode) else {
            setRepeatMode(order[0])
            return
        }
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
        case .wholeTrack, .playlist, .off:
            playerService.setLoopSegment(nil)
        }
    }
    
    /// 与播放器同步单句循环目标（时间轴编辑等之后调用）
    func syncRepeatModeWithPlayer() {
        switch repeatMode {
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
        case .wholeTrack, .playlist, .off:
            playerService.setLoopSegment(nil)
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
        let sourceTokens = segment.userTokenOverrides ?? segment.tokens
        editingTokenReadings = Self.makeEditableTokenReadings(from: sourceTokens)
        editingTokenSegmentationText = sourceTokens.map(\.surface).joined(separator: "|")
        editingSkipFurigana = segment.skipFurigana
        editingStartTime = segment.startTime
        editingEndTime = segment.endTime
    }

    /// 編集をキャンセルする
    func cancelEditing() {
        editingSegmentID = nil
        editingText = ""
        editingTranslatedText = nil
        editingTokenReadings = []
        editingTokenSegmentationText = ""
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
        let editingItemsSnapshot = editingTokenReadings
        let userOverrideTokens = Self.makeUserOverrideTokens(from: editingTokenReadings)
        let segmentIndex = index
        let originalTextBeforeEditing = document.segments[index].originalText
        let duration = playerService.duration
        let clampedStart = max(0, min(editingStartTime, duration))
        let clampedEnd = max(clampedStart, min(editingEndTime, duration > 0 ? duration : editingEndTime))
        
        print("PlayerViewModel: 編集を確定中... text=\(newText), skip=\(shouldSkip), start=\(clampedStart), end=\(clampedEnd)")
        
        Task {
            // 1. 新しい振り仮名を生成（非メインスレッド）
            let generatedTokens: [FuriganaToken] = shouldSkip
                ? []
                : await furiganaService.generateFurigana(for: newText)
            let tokens: [FuriganaToken] = shouldSkip ? [] : generatedTokens
            if !shouldSkip {
                self.syncKatakanaDictionaryFromEdits(editingItemsSnapshot)
            }
            
            // 2. メインスレッドでドキュメントを更新して保存
            await MainActor.run {
                // インデックスガード
                guard segmentIndex < self.document.segments.count else { return }
                
                // プロパティを個別に更新
                self.document.segments[segmentIndex].startTime = clampedStart
                self.document.segments[segmentIndex].endTime = clampedEnd
                self.document.segments[segmentIndex].originalText = newText
                self.document.segments[segmentIndex].tokens = tokens
                let shouldKeepOverride = Self.shouldKeepUserTokenOverrides(
                    userOverrideTokens: userOverrideTokens,
                    newText: newText,
                    oldText: originalTextBeforeEditing
                )
                self.document.segments[segmentIndex].userTokenOverrides = shouldSkip
                    ? nil
                    : (shouldKeepOverride ? (userOverrideTokens.isEmpty ? nil : userOverrideTokens) : nil)
                self.document.segments[segmentIndex].skipFurigana = shouldSkip
                self.document.segments[segmentIndex].translatedText = self.editingTranslatedText
                self.editingTranslatedText = nil
                self.editingTokenReadings = []
                self.editingTokenSegmentationText = ""
                
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
            translatedText: segment.translatedText,
            userTokenOverrides: segment.userTokenOverrides,
            originalTextLanguageCode: segment.originalTextLanguageCode
        )
        let second = TranscriptSegment(
            startTime: t,
            endTime: segment.endTime,
            originalText: segment.originalText,
            tokens: segment.tokens,
            confidence: segment.confidence,
            skipFurigana: segment.skipFurigana,
            translatedText: segment.translatedText,
            userTokenOverrides: segment.userTokenOverrides,
            originalTextLanguageCode: segment.originalTextLanguageCode
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
        let sourceTokens = second.userTokenOverrides ?? second.tokens
        editingTokenReadings = Self.makeEditableTokenReadings(from: sourceTokens)
        editingTokenSegmentationText = sourceTokens.map(\.surface).joined(separator: "|")
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
        let mergedLang: String? = (prev.originalTextLanguageCode == current.originalTextLanguageCode)
            ? prev.originalTextLanguageCode
            : nil
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
                self.document.segments[targetIndex].userTokenOverrides = nil
                self.document.segments[targetIndex].skipFurigana = shouldSkip
                self.document.segments[targetIndex].translatedText = nil
                self.document.segments[targetIndex].originalTextLanguageCode = mergedLang
                
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
                self.editingTokenReadings = Self.makeEditableTokenReadings(from: self.document.segments[targetIndex].tokens)
                self.editingTokenSegmentationText = self.document.segments[targetIndex].tokens.map(\.surface).joined(separator: "|")
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
        // 不在此处预探测翻译：预探测失败会弹「网络/语言包」提示后仍继续正式批量翻译，
        // 极易再次失败并弹出「翻译失败」，造成连续两个弹窗且误导用户。
        isTranslating = true
        defer { isTranslating = false }
        do {
            let result = try await translationService.translateSegments(
                segments,
                targetLanguageCode: targetLanguageCode,
                documentNonJapaneseRecognitionSource: document.isNonJapaneseRecognitionSource
            )
            markTranslationPackReady(targetLanguageCode)
            document.segments = result
            // 同步翻译状态：成功后清除"翻译失败"提示
            document.translationStatus = .success
            playerService.setSegments(document.segments)
            syncRepeatModeWithPlayer()
            saveDocument()
            showTranslation = true
        } catch {
            print("PlayerViewModel: 翻译全部失败 - \(error)")
            // 翻译再次失败：更新状态以便提示横条继续显示
            document.translationStatus = .failed
            saveDocument()
            translationErrorMessage = translationFailureUserMessage(for: error)
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
            let segmentSource = editingSegmentID.flatMap { id in
                document.segments.first(where: { $0.id == id })?.originalTextLanguageCode
            }
            let translated = try await translationService.translateText(
                text,
                segmentSourceLanguageCode: segmentSource,
                targetLanguageCode: targetLang,
                documentNonJapaneseRecognitionSource: document.isNonJapaneseRecognitionSource
            )
            markTranslationPackReady(targetLang)
            editingTranslatedText = translated.isEmpty ? nil : translated
        } catch {
            print("PlayerViewModel: 单条翻译失败 - \(error)")
            translationErrorMessage = translationFailureUserMessage(for: error)
            showTranslationError = true
        }
    }

    /// 系统 Translation 在未安装目标语言数据等原因失败时，localizedDescription 往往只有「无法翻译」；补充可操作的说明
    private func translationFailureUserMessage(for error: Error) -> String {
        if (error as? TranslationServiceError) == .notAvailable {
            return String(localized: LocalizedStringResource("translation_requires_newer_ios", locale: AppLocale.current))
        }
        let explanation = String(localized: LocalizedStringResource("translation_failed_explanation", locale: AppLocale.current))
        let networkHint = String(localized: LocalizedStringResource("translation_network_hint_message", locale: AppLocale.current))
        var body = explanation + "\n\n" + networkHint
        let detail = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !detail.isEmpty {
            body += "\n\n(" + detail + ")"
        }
        return body
    }

    /// - Parameter userChangedTarget: 仅当用户在播放页菜单中**切换到另一翻译目标**时为 `true`。
    ///   默认/首次安装跟随系统语言时不应预探测，避免「开始翻译」前误弹网络/语言包提示；直接翻译失败时已有统一说明。
    @MainActor
    func setTargetLanguageCode(_ code: String, userChangedTarget: Bool = false) async {
        let normalized = TranslationTargetLanguageOptions.normalizedCode(code)
        let previous = targetLanguageCode
        targetLanguageCode = normalized
        guard userChangedTarget, normalized != previous else { return }
        await prepareTargetLanguagePackIfNeeded()
    }

    @MainActor
    private func prepareTargetLanguagePackIfNeeded() async {
        if !TranslationService.isAvailableOnCurrentSystem { return }
        let code = targetLanguageCode
        guard !isTranslationPackReady(code) else { return }
        do {
            _ = try await translationService.translateText(
                "こんにちは",
                segmentSourceLanguageCode: "ja",
                targetLanguageCode: code,
                documentNonJapaneseRecognitionSource: nil
            )
            markTranslationPackReady(code)
        } catch {
            if (error as? TranslationServiceError) == .notAvailable { return }
            if shouldShowTranslationPackHint(for: code) {
                showTranslationNetworkHint = true
                markTranslationPackHintShown(code)
            }
        }
    }

    private func isTranslationPackReady(_ code: String) -> Bool {
        let list = Self.defaults.array(forKey: Self.translationPackReadyCodesKey) as? [String] ?? []
        return Set(list).contains(code)
    }

    private func markTranslationPackReady(_ code: String) {
        var set = Set(Self.defaults.array(forKey: Self.translationPackReadyCodesKey) as? [String] ?? [])
        set.insert(code)
        Self.defaults.set(Array(set), forKey: Self.translationPackReadyCodesKey)
    }

    private func shouldShowTranslationPackHint(for code: String) -> Bool {
        let list = Self.defaults.array(forKey: Self.translationPackHintShownCodesKey) as? [String] ?? []
        return !Set(list).contains(code)
    }

    private func markTranslationPackHintShown(_ code: String) {
        var set = Set(Self.defaults.array(forKey: Self.translationPackHintShownCodesKey) as? [String] ?? [])
        set.insert(code)
        Self.defaults.set(Array(set), forKey: Self.translationPackHintShownCodesKey)
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
                
                let recLang = UserDefaults.standard.string(forKey: WhisperSpeechRecognitionService.sourceLanguageDefaultsKey) ?? "ja"
                var transcriptSegments: [TranscriptSegment] = []
                for seg in srtSegments {
                    let isJapanese = WhisperSpeechRecognitionService.isLikelyJapanese(seg.text)
                    let tokens = await furiganaService.generateFurigana(for: seg.text)
                    let lineLang = WhisperSpeechRecognitionService.storedOriginalTextLanguageCode(
                        recognitionUserSetting: recLang,
                        lineLooksJapanese: isJapanese
                    )
                    transcriptSegments.append(TranscriptSegment(
                        startTime: seg.startTime,
                        endTime: seg.endTime,
                        originalText: seg.text,
                        tokens: tokens,
                        originalTextLanguageCode: lineLang
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
                    document.isNonJapaneseRecognitionSource = importedDoc.isNonJapaneseRecognitionSource
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

    // MARK: - 逐词注音编辑

    private static func makeEditableTokenReadings(from tokens: [FuriganaToken]) -> [EditableTokenReading] {
        tokens.map {
            let hasMeaning = (($0.englishMeaning?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) == false)
            return EditableTokenReading(
                id: $0.id,
                surface: $0.surface,
                reading: $0.reading,
                romaji: $0.romaji,
                isKatakana: $0.isKatakana,
                englishMeaning: $0.englishMeaning,
                startTime: $0.startTime,
                endTime: $0.endTime,
                partOfSpeech: $0.partOfSpeech,
                englishMeaningEnabled: $0.isKatakana || hasMeaning
            )
        }
    }

    private static func makeUserOverrideTokens(from items: [EditableTokenReading]) -> [FuriganaToken] {
        items.compactMap { item in
            let surface = item.surface.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !surface.isEmpty else { return nil }
            let reading = item.reading.trimmingCharacters(in: .whitespacesAndNewlines)
            let romaji = item.romaji.trimmingCharacters(in: .whitespacesAndNewlines)
            let englishMeaning = item.englishMeaning?.trimmingCharacters(in: .whitespacesAndNewlines)
            let shouldStoreMeaning = item.englishMeaningEnabled
            let isKanji = containsKanji(surface)
            let isKatakana = item.isKatakana || isKatakanaWord(surface)
            return FuriganaToken(
                surface: surface,
                reading: reading,
                romaji: romaji,
                isKanji: isKanji,
                isKatakana: isKatakana,
                englishMeaning: (shouldStoreMeaning && englishMeaning?.isEmpty == false) ? englishMeaning : nil,
                startTime: item.startTime,
                endTime: item.endTime,
                partOfSpeech: item.partOfSpeech
            )
        }
    }

    private func syncKatakanaDictionaryFromEdits(_ items: [EditableTokenReading]) {
        for item in items where item.englishMeaningEnabled {
            let surface = item.surface.trimmingCharacters(in: .whitespacesAndNewlines)
            let meaning = (item.englishMeaning ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !surface.isEmpty, !meaning.isEmpty else { continue }
            guard item.isKatakana || Self.isKatakanaWord(surface) else { continue }
            KatakanaDictionaryService.shared.upsert(surface: surface, englishMeaning: meaning)
        }
    }

    /// 仅当用户覆盖分词与新文本仍一致时才保留覆盖；
    /// 否则清空覆盖，避免「显示旧词块但编辑框是新文本」的不一致。
    private static func shouldKeepUserTokenOverrides(userOverrideTokens: [FuriganaToken], newText: String, oldText: String) -> Bool {
        guard !userOverrideTokens.isEmpty else { return false }
        let normalizedNew = normalizeComparableText(newText)
        let normalizedOld = normalizeComparableText(oldText)
        // 文本没变时保留覆盖（例如只改注音/罗马音）
        if normalizedNew == normalizedOld { return true }
        let joinedOverride = normalizeComparableText(userOverrideTokens.map(\.surface).joined())
        return joinedOverride == normalizedNew
    }

    private static func normalizeComparableText(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    }

    private static func containsKanji(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value)
        }
    }

    private static func isKatakanaWord(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        var hasKatakana = false
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if (0x30A0...0x30FF).contains(v) {
                hasKatakana = true
                continue
            }
            if v == 0x30FC || v == 0x30FB {
                continue
            }
            return false
        }
        return hasKatakana
    }

    func applyManualSegmentationFromEditingText() {
        let source = editingTokenSegmentationText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return }
        let parts = source
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return }
        let previousItems = editingTokenReadings
        var cursor = 0
        var rebuilt: [EditableTokenReading] = []

        for part in parts {
            var consumed: [EditableTokenReading] = []
            var joinedSurface = ""
            var scan = cursor

            // 优先按顺序消费旧词块：支持“把左右两个词块合并成一个词块”
            while scan < previousItems.count {
                let candidate = previousItems[scan]
                let nextSurface = joinedSurface + candidate.surface
                if part.hasPrefix(nextSurface) {
                    consumed.append(candidate)
                    joinedSurface = nextSurface
                    scan += 1
                    if joinedSurface == part {
                        cursor = scan
                        break
                    }
                } else {
                    break
                }
            }

            if joinedSurface == part, !consumed.isEmpty {
                rebuilt.append(Self.mergeEditableItems(consumed, targetSurface: part))
                continue
            }

            // 兜底：按 surface 精确匹配一个旧词块（处理用户跨位置编辑）
            if let matched = previousItems.first(where: { $0.surface == part }) {
                rebuilt.append(
                    EditableTokenReading(
                        id: UUID(),
                        surface: part,
                        reading: matched.reading,
                        romaji: matched.romaji,
                        isKatakana: matched.isKatakana || Self.isKatakanaWord(part),
                        englishMeaning: matched.englishMeaning,
                        startTime: matched.startTime,
                        endTime: matched.endTime,
                        partOfSpeech: matched.partOfSpeech,
                        englishMeaningEnabled: matched.englishMeaningEnabled
                    )
                )
                continue
            }

            // 完全新建的词块
            rebuilt.append(
                EditableTokenReading(
                    id: UUID(),
                    surface: part,
                    reading: Self.containsKanji(part) ? part : "",
                    romaji: "",
                    isKatakana: Self.isKatakanaWord(part),
                    englishMeaning: nil,
                    startTime: nil,
                    endTime: nil,
                    partOfSpeech: nil,
                    englishMeaningEnabled: Self.isKatakanaWord(part)
                )
            )
        }
        editingTokenReadings = rebuilt
        editingTokenSegmentationText = rebuilt.map(\.surface).joined(separator: "|")
    }

    private static func mergeEditableItems(_ items: [EditableTokenReading], targetSurface: String) -> EditableTokenReading {
        let mergedReading = items.map(\.reading).joined()
        let mergedRomaji = items.map(\.romaji).joined()
        let meanings = items.compactMap { item -> String? in
            let value = item.englishMeaning?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return value.isEmpty ? nil : value
        }
        let mergedMeaning = meanings.isEmpty ? nil : meanings.joined(separator: " / ")
        let firstStart = items.compactMap(\.startTime).min()
        let lastEnd = items.compactMap(\.endTime).max()
        let katakana = items.contains(where: \.isKatakana) || isKatakanaWord(targetSurface)
        let meaningEnabled = items.contains(where: \.englishMeaningEnabled) || katakana

        return EditableTokenReading(
            id: UUID(),
            surface: targetSurface,
            reading: mergedReading,
            romaji: mergedRomaji,
            isKatakana: katakana,
            englishMeaning: mergedMeaning,
            startTime: firstStart,
            endTime: lastEnd,
            partOfSpeech: nil,
            englishMeaningEnabled: meaningEnabled
        )
    }
}
