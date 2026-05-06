//
//  PlayerView.swift
//  YomiPlay
//
//  プレーヤー画面
//  字幕表示 + 再生コントロール + 設定シート + 字幕編集
//

import SwiftUI
import AVKit
import Translation
import UniformTypeIdentifiers

// MARK: - AVPlayer ネイティブコントロール非表示ラッパー

private struct VideoPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = false
        vc.videoGravity = .resizeAspect
        return vc
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
            uiViewController.player = player
        }
    }
}

// MARK: - プレーヤー画面

struct PlayerView: View {
    @Binding var navigationPath: NavigationPath
    @State private var viewModel: PlayerViewModel
    @State private var playlist: [TranscriptDocument]
    @State private var currentIndex: Int
    @State private var showSettings: Bool = false
    @State private var shadowReadingSegment: TranscriptSegment?
    @State private var shouldAutoPlayOnReady: Bool = false
    @State private var pinchScale: CGFloat = 1.0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var systemColorScheme
    @AppStorage(PlayerTheme.playerThemeStorageKey) private var playerTheme: String = "system"
    /// 首次进入播放页时提示「长按字幕可编辑」；点「知道了」后不再显示
    @AppStorage("playerSubtitleLongPressHintSeen") private var hasSeenLongPressSubtitleHint: Bool = false
    /// 用户在该文档上手动忽略的"翻译失败"提示集合（按 doc id）。重试成功会自动从集合移除。
    @AppStorage("playerTranslationFailedDismissedDocIds") private var dismissedTranslationFailedDocIdsRaw: String = ""
    
    /// 实际用于播放器界面的主题（用户选择或跟随系统）
    private var effectiveThemeScheme: ColorScheme {
        if playerTheme == "light" { return .light }
        if playerTheme == "dark" { return .dark }
        return systemColorScheme
    }
    
    init(documents: [TranscriptDocument], currentIndex: Int, navigationPath: Binding<NavigationPath>) {
        let safeIndex = max(0, min(documents.count - 1, currentIndex))
        // 从存储重新加载，保证进入播放页看到的是最新保存内容
        let playlist = documents.isEmpty ? [] : documents.map { DocumentStore.shared.load(id: $0.id) ?? $0 }
        let initialDocument = playlist.isEmpty ? TranscriptDocument(source: AudioSource(type: .local, title: "")) : playlist[safeIndex]
        self._navigationPath = navigationPath
        self._viewModel = State(initialValue: PlayerViewModel(document: initialDocument))
        self._playlist = State(initialValue: playlist.isEmpty ? [initialDocument] : playlist)
        self._currentIndex = State(initialValue: safeIndex)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 動画エリア（動画ファイルの場合のみ表示）
            if viewModel.videoPlaybackURL != nil, let player = viewModel.playerService.player {
                VStack(spacing: 0) {
                    VideoPlayerView(player: player)
                        .aspectRatio(16/9, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipped()
                }
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(.systemGray5).opacity(0.8), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            
            // 字幕エリア（首次进入且有条目时展示一次性长按提示；自动翻译失败也单独提示）
            Group {
                if !hasSeenLongPressSubtitleHint, !viewModel.document.segments.isEmpty {
                    longPressSubtitleHintBanner
                }
                if shouldShowTranslationFailedBanner {
                    translationFailedBanner
                }
                transcriptSection
            }
            
            Divider()
                .overlay(Color(.systemGray4))
            
            // 再生コントロール
            controlsSection
        }
        .environment(\.playerThemeScheme, effectiveThemeScheme)
        .tint(PlayerTheme.palette(for: effectiveThemeScheme).accent)
        .navigationTitle(viewModel.document.source.title.isEmpty ? String(localized: "now_playing") : viewModel.document.source.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    viewModel.playerService.pause()
                    // 使用系统的 dismiss 回到上一层，避免直接操作 NavigationPath 导致状态异常
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("home")
                    }
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheetView(viewModel: viewModel)
                .presentationDetents(settingsSheetDetents)
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $shadowReadingSegment) { segment in
            ShadowReadingPracticeSheet(
                segment: segment,
                locale: locale,
                onDismiss: { shadowReadingSegment = nil },
                onPausePlayback: { viewModel.playerService.pause() }
            )
        }
        .onDisappear {
            viewModel.playerService.pause()
            viewModel.savePlaybackPosition()
        }
        .onChange(of: viewModel.playerService.isAudioReady) { _, ready in
            guard ready else { return }
            if shouldAutoPlayOnReady {
                // 自動で次の記録へ進んだ場合のみ、読み込み完了後に再生開始
                viewModel.seek(to: 0)
                viewModel.togglePlayPause()
                shouldAutoPlayOnReady = false
            }
        }
        .onAppear {
            // 再生完了時に次の記録へ進む
            viewModel.playerService.onPlaybackEnded = {
                switch viewModel.repeatMode {
                case .wholeTrack:
                    viewModel.playerService.seek(to: 0)
                    viewModel.playerService.play()
                case .playlist:
                    playNextIfAvailable(loopToStart: true)
                case .off:
                    break
                case .currentSubtitle:
                    playNextIfAvailable()
                }
            }
        }
    }
    
    /// 是否需要在播放页顶部显示「自动翻译失败」提示横条
    private var shouldShowTranslationFailedBanner: Bool {
        guard viewModel.document.translationStatus == .failed else { return false }
        guard !viewModel.document.segments.isEmpty else { return false }
        let dismissed = Set(dismissedTranslationFailedDocIdsRaw.split(separator: ",").map(String.init))
        return !dismissed.contains(viewModel.document.id.uuidString)
    }

    private func dismissTranslationFailedBanner() {
        var set = Set(dismissedTranslationFailedDocIdsRaw.split(separator: ",").map(String.init))
        set.insert(viewModel.document.id.uuidString)
        dismissedTranslationFailedDocIdsRaw = set.sorted().joined(separator: ",")
    }

    /// 自动翻译失败的轻量提示横条：解释原因 + 提供「重试」按钮
    private var translationFailedBanner: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.bubble")
                .font(.body)
                .foregroundStyle(Color.orange)
                .accessibilityHidden(true)
            Text("player_translation_failed_hint")
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button {
                Task { await viewModel.translateAllSegments() }
            } label: {
                if viewModel.isTranslating {
                    ProgressView().controlSize(.small)
                } else {
                    Text("player_translation_failed_retry")
                        .font(.subheadline.weight(.semibold))
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(viewModel.isTranslating)

            Button {
                dismissTranslationFailedBanner()
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("player_translation_failed_dismiss_a11y"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
    }

    private var longPressSubtitleHintBanner: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "hand.tap.fill")
                .font(.body)
                .foregroundStyle(PlayerTheme.palette(for: effectiveThemeScheme).accent.opacity(0.9))
                .accessibilityHidden(true)
            Text("player_subtitle_long_press_hint")
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button {
                hasSeenLongPressSubtitleHint = true
            } label: {
                Text("player_subtitle_long_press_hint_ok")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
    }
    
    // MARK: - 字幕セクション
    
    private var transcriptSection: some View {
        let effectiveFontSize = max(12, min(viewModel.fontSize * pinchScale, 48))
        
        return TranscriptView(
            segments: viewModel.document.segments,
            currentSegmentID: viewModel.playerService.currentSegmentID,
            currentTime: viewModel.playerService.subtitleClockTime,
            showFurigana: viewModel.showFurigana,
            showRomaji: viewModel.showRomaji,
            showEnglish: viewModel.showEnglish,
            showPrimaryTranslation: viewModel.showPrimaryTranslation,
            showSecondaryTranslation: viewModel.showSecondaryTranslation,
            primaryTranslationLanguageCode: viewModel.primaryTargetLanguageCode,
            secondaryTranslationLanguageCode: viewModel.secondaryTargetLanguageCode,
            fontSize: effectiveFontSize,
            editingSegmentID: viewModel.editingSegmentID,
            editingText: $viewModel.editingText,
            editingPrimaryTranslatedText: Binding(get: { viewModel.editingPrimaryTranslatedText }, set: { viewModel.editingPrimaryTranslatedText = $0 }),
            editingSecondaryTranslatedText: Binding(get: { viewModel.editingSecondaryTranslatedText }, set: { viewModel.editingSecondaryTranslatedText = $0 }),
            editingTokenReadings: $viewModel.editingTokenReadings,
            editingTokenSegmentationText: $viewModel.editingTokenSegmentationText,
            editingSkipFurigana: $viewModel.editingSkipFurigana,
            editingStartTime: $viewModel.editingStartTime,
            editingEndTime: $viewModel.editingEndTime,
            isTranslating: viewModel.isTranslating,
            showShadowReadingMic: viewModel.showShadowReadingMic,
            onSegmentTapped: { segment in
                viewModel.onSegmentTapped(segment)
            },
            onEditTapped: { segment in
                viewModel.playerService.pause()
                viewModel.startEditing(segment: segment)
            },
            onEditConfirmed: {
                viewModel.confirmEditing()
            },
            onEditCancelled: {
                viewModel.cancelEditing()
            },
            onDeleteSegment: {
                viewModel.deleteCurrentSegment()
            },
            onSplitSegment: {
                viewModel.splitCurrentSegmentAtCurrentTime()
            },
            onMergeWithPrevious: {
                viewModel.mergeCurrentWithPrevious()
            },
            onApplyManualSegmentation: {
                viewModel.applyManualSegmentationFromEditingText()
            },
            onTranslateThisSegment: {
                await viewModel.translateCurrentSegment()
            },
            onShadowReadingTapped: { segment in
                viewModel.playerService.pause()
                shadowReadingSegment = segment
            }
        )
        .gesture(
            MagnificationGesture()
                .onChanged { value in
                    pinchScale = value
                }
                .onEnded { value in
                    let newSize = max(12, min(viewModel.fontSize * value, 48))
                    viewModel.fontSize = newSize
                    pinchScale = 1.0
                }
        )
    }
    
    // MARK: - 再生コントロール
    
    private var controlsSection: some View {
        let service = viewModel.playerService
        return PlaybackControlsView(
            isPlaying: service.isPlaying,
            currentTime: service.currentTime,
            duration: service.duration,
            playbackRateText: viewModel.playbackRateText,
            playbackRate: viewModel.playbackRate,
            availablePlaybackRates: PlayerViewModel.availableRates,
            repeatMode: viewModel.repeatMode,
            onTogglePlayPause: { viewModel.togglePlayPause() },
            onSkipBackward: { viewModel.skipBackward() },
            onSkipForward: { viewModel.skipForward() },
            onSeek: { time in viewModel.seek(to: time) },
            onCycleRate: { viewModel.cyclePlaybackRate() },
            onSelectRate: { viewModel.setPlaybackRate($0) },
            onSelectRepeatMode: { viewModel.setRepeatMode($0) },
            onCycleRepeatMode: { viewModel.cycleRepeatMode() }
        )
    }

    private var settingsSheetDetents: Set<PresentationDetent> {
        // iPad 的默认 sheet 容易卡在 medium，导致内容高度“够但没展开”
        horizontalSizeClass == .regular ? Set([.large, .medium]) : Set([.medium])
    }
    
    // MARK: - プレイリスト制御
    
    private func playNextIfAvailable(loopToStart: Bool = false) {
        let nextIndex = currentIndex + 1
        let targetIndex: Int
        if nextIndex < playlist.count {
            targetIndex = nextIndex
        } else if loopToStart, !playlist.isEmpty {
            targetIndex = 0
        } else {
            return
        }
        let nextDoc = playlist[targetIndex]
        let nextDocument = DocumentStore.shared.load(id: nextDoc.id) ?? nextDoc
        currentIndex = targetIndex
        viewModel = PlayerViewModel(document: nextDocument)
        shouldAutoPlayOnReady = true
        // onPlaybackEnded ハンドラを新しいプレイヤーに再設定
        viewModel.playerService.onPlaybackEnded = {
            switch viewModel.repeatMode {
            case .wholeTrack:
                viewModel.playerService.seek(to: 0)
                viewModel.playerService.play()
            case .playlist:
                playNextIfAvailable(loopToStart: true)
            case .off:
                break
            case .currentSubtitle:
                playNextIfAvailable()
            }
        }
    }
}

// MARK: - 共有用の URL ラッパー（Identifiable）

private struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - 設定シートビュー

/// 导出类型，用于统一分享弹窗的标题、图标与按钮文案
private enum ExportKind: String {
    case media
    case srt
    case yomi
}

/// 导出完成后的分享项（音视频 / SRT / YOMI 共用同一弹窗）
private struct ExportShareItem: Identifiable {
    let id = UUID()
    let kind: ExportKind
    let url: URL
}

struct SettingsSheetView: View {
    @Environment(\.locale) private var locale
    @Bindable var viewModel: PlayerViewModel
    @AppStorage(PlayerTheme.playerThemeStorageKey) private var playerTheme: String = "system"
    @State private var selectedTab = 0
    @State private var exportShareItem: ExportShareItem?
    @State private var isFileImporterPresented: Bool = false
    @State private var hasExportedSRT: Bool = false
    @State private var hasExportedYomi: Bool = false
    @State private var hasExportedAudio: Bool = false

    enum ImportMode { case srt, yomi }
    @State private var importMode: ImportMode = .srt

    // エクスポート中のステータス
    @State private var isExporting: Bool = false
    @State private var exportProgress: Double = 0.0
    @State private var exportingType: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("general").tag(0)
                Text("learning").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            if selectedTab == 0 {
                ScrollView {
                    VStack(spacing: 20) {
                        generalSettings
                        exportSection
                        importSection
                    }
                    .padding(.vertical, 16)
                }
            } else {
                ScrollView {
                    learningSettings
                }
            }
            
            Spacer()
        }
        .background(Color(.systemGroupedBackground))
        .overlay {
            if isExporting {
                exportingOverlay
            }
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: importMode == .srt ? [.plainText] : [.yomiDocument, .json],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                switch importMode {
                case .srt: viewModel.importSRT(from: url)
                case .yomi: viewModel.importYomi(from: url)
                }
            }
        }
        .alert("subtitles_imported", isPresented: $viewModel.showSRTImportSuccess) {
            Button("ok") {}
        } message: {
            Text(verbatim: "\(viewModel.document.segments.count) " + String(localized: "segments_updated"))
        }
        .alert("subtitles_imported", isPresented: $viewModel.showYomiImportSuccess) {
            Button("ok") {}
        } message: {
            Text(verbatim: "\(viewModel.document.segments.count) " + String(localized: "segments_updated"))
        }
        .alert("translation_failed", isPresented: $viewModel.showTranslationError) {
            Button("ok") { viewModel.showTranslationError = false }
        } message: {
            Text(viewModel.translationErrorMessage ?? String(localized: "unknown_error"))
        }
        .alert(String(localized: LocalizedStringResource("translation_network_hint_title", locale: locale)), isPresented: $viewModel.showTranslationNetworkHint) {
            Button("ok") { viewModel.showTranslationNetworkHint = false }
        } message: {
            Text(String(localized: LocalizedStringResource("translation_network_hint_message", locale: locale)))
        }
        .sheet(item: $exportShareItem) { item in
            exportShareSheet(item: item)
        }
    }
    
    /// 统一导出分享弹窗：根据导出类型显示对应标题、图标与「分享」按钮文案
    @ViewBuilder
    private func exportShareSheet(item: ExportShareItem) -> some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 类型图标与标题
                VStack(spacing: 16) {
                    exportIcon(for: item.kind)
                    Text(exportSheetTitle(for: item.kind))
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text(item.url.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal)
                    if item.kind == .yomi {
                        Text("full_subtitle_file_with_furigana_translations_etc")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                }
                .padding(.top, 28)
                .padding(.bottom, 24)
                
                // 分享按钮 + 关闭
                VStack(spacing: 16) {
                    shareLink(for: item)
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    
                    Button("close") {
                        markExported(for: item.kind)
                        exportShareItem = nil
                    }
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemGroupedBackground))
            .navigationTitle(exportSheetTitle(for: item.kind))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func exportIcon(for kind: ExportKind) -> some View {
        Group {
            switch kind {
            case .media:
                Image(systemName: viewModel.document.source.videoPlaybackURL != nil ? "play.rectangle.fill" : "waveform")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(.green)
            case .srt:
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(.blue)
            case .yomi:
                Image("yomi-mark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }
    
    private func exportSheetTitle(for kind: ExportKind) -> String {
        switch kind {
        case .media: return String(localized: "share_media")
        case .srt: return String(localized: "export_subtitles_srt")
        case .yomi: return String(localized: "player_export_yomi_title")
        }
    }
    
    private func exportShareButtonTitle(for kind: ExportKind) -> String {
        switch kind {
        case .media: return String(localized: "share_media")
        case .srt, .yomi: return String(localized: "share_subtitles")
        }
    }
    
    @ViewBuilder
    private func shareLink(for item: ExportShareItem) -> some View {
        switch item.kind {
        case .media:
            ShareLink(item: item.url, preview: SharePreview(viewModel.document.source.title, image: Image(systemName: "waveform"))) {
                Label(exportShareButtonTitle(for: item.kind), systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
        case .srt:
            ShareLink(item: item.url, preview: SharePreview("SRT", image: Image(systemName: "doc.text"))) {
                Label(exportShareButtonTitle(for: item.kind), systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
        case .yomi:
            ShareLink(item: item.url, preview: SharePreview("YomiPlay", image: Image("yomi-mark"))) {
                Label(exportShareButtonTitle(for: item.kind), systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
        }
    }
    
    private func markExported(for kind: ExportKind) {
        switch kind {
        case .media: hasExportedAudio = true
        case .srt: hasExportedSRT = true
        case .yomi: hasExportedYomi = true
        }
    }
    
    private var exportingTitle: String {
        switch exportingType {
        case "SRT":
            return String(localized: "export_subtitles_srt")
        case "YOMI":
            return String(localized: "player_export_yomi_title")
        case "Media":
            return String(localized: "settings_export_media_title")
        default:
            return ""
        }
    }
    
    private var exportingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            VStack(spacing: 20) {
                ProgressView(value: exportProgress, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(.green)
                    .frame(width: 200)
                
                Text(exportingTitle.isEmpty ? "..." : "\(exportingTitle)...")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .padding(32)
            .background(.ultraThinMaterial)
            .cornerRadius(20)
            .shadow(radius: 10)
        }
    }
    
    private func runExportTask(type: String, action: @escaping () -> URL?) {
        exportingType = type
        isExporting = true
        exportProgress = 0.0
        
        HapticManager.shared.impact(style: .medium)
        
        // 擬似的なプログレス（プレミアム感を出すため）
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            exportProgress += 0.2
            if exportProgress >= 1.0 {
                timer.invalidate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    if let url = action() {
                        HapticManager.shared.success()
                        let kind: ExportKind
                        switch type {
                        case "SRT": kind = .srt
                        case "YOMI": kind = .yomi
                        default: kind = .media
                        }
                        exportShareItem = ExportShareItem(kind: kind, url: url)
                    }
                    isExporting = false
                }
            }
        }
    }
    
    private var generalSettings: some View {
        VStack(spacing: 0) {
            settingsRow(icon: "textformat.size", title: "font_size", color: .green) {
                HStack(spacing: 12) {
                    Button { viewModel.adjustFontSize(by: -2) } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title3).foregroundStyle(.green)
                    }.disabled(viewModel.fontSize <= 12)
                    
                    Text("\(Int(viewModel.fontSize))")
                        .font(.subheadline)
                        .monospacedDigit()
                        // 两位数时避免在 iPad 上换行（32 宽度不够）
                        .frame(width: 46, alignment: .center)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    
                    Button { viewModel.adjustFontSize(by: 2) } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3).foregroundStyle(.green)
                    }.disabled(viewModel.fontSize >= 48)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .padding(.horizontal, 16)
    }
    
    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("export").font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                .padding(.horizontal, 20)
            
            VStack(spacing: 0) {
                // Media Export (audio or video)
                if let url = viewModel.document.source.playbackURL {
                    exportRow(
                        icon: "waveform",
                        title: "settings_export_media_title",
                        color: .green,
                        hasExported: hasExportedAudio,
                        isExporting: isExporting && exportingType == "Media"
                    ) {
                        runExportTask(type: "Media") { url }
                    }
                    Divider().padding(.leading, 52)
                }
                
                // SRT Export
                exportRow(
                    icon: "doc.text",
                    title: "export_subtitles_srt",
                    color: .blue,
                    hasExported: hasExportedSRT,
                    isExporting: isExporting && exportingType == "SRT"
                ) {
                    runExportTask(type: "SRT") {
                        SubtitleExportService.writeSRTToTempFile(
                            segments: viewModel.document.segments,
                            fileName: viewModel.document.source.title
                        )
                    }
                }
                
                Divider().padding(.leading, 52)
                
                // YOMI Export
                exportRow(
                    icon: "character.bubble.fill",
                    title: "player_export_yomi_title",
                    color: .orange,
                    hasExported: hasExportedYomi,
                    isExporting: isExporting && exportingType == "YOMI"
                ) {
                    runExportTask(type: "YOMI") {
                        SubtitleExportService.writeYomiToTempFile(
                            document: viewModel.document,
                            fileName: viewModel.document.source.title
                        )
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
            .padding(.horizontal, 16)
        }
    }
    
    private var importSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("import").font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                .padding(.horizontal, 20)
            
            VStack(spacing: 0) {
                settingsRow(icon: "square.and.arrow.down", title: "import_subtitles_srt", color: .green) {
                    if viewModel.isImportingSRT {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("select_file") {
                            importMode = .srt
                            isFileImporterPresented = true
                        }
                        .font(.subheadline).foregroundStyle(.green)
                    }
                }
                
                Divider().padding(.leading, 52)
                
                settingsRow(icon: "square.and.arrow.down.fill", title: "player_import_yomi_title", color: .green) {
                    if viewModel.isImportingYomi {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("select_file") {
                            importMode = .yomi
                            isFileImporterPresented = true
                        }
                        .font(.subheadline).foregroundStyle(.green)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
            .padding(.horizontal, 16)
        }
    }
    
    private func exportRow(
        icon: String,
        title: LocalizedStringKey,
        color: Color,
        hasExported: Bool,
        isExporting: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.body).foregroundStyle(color).frame(width: 28)
                Text(title).font(.subheadline)
                Spacer()
                if isExporting {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.green)
                } else if hasExported {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isExporting ? Color.green.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .disabled(isExporting)
    }
    
    private var learningSettings: some View {
        VStack(spacing: 16) {
            practiceReadingSection
            
            VStack(spacing: 0) {
                Text("translation")
                    .font(.caption).fontWeight(.semibold).foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.bottom, 8)
                
                VStack(spacing: 0) {
                    settingsRow(icon: "globe", title: "target_language_primary", color: .green) {
                        Menu {
                            ForEach(TranslationTargetLanguageOptions.allCodes, id: \.self) { code in
                                Button {
                                    Task { await viewModel.setPrimaryTargetLanguageCode(code, userChangedTarget: true) }
                                } label: {
                                    Text(TranslationTargetLanguageOptions.displayName(code: code, locale: locale))
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(labelForLanguage(code: viewModel.primaryTargetLanguageCode))
                                    .font(.subheadline)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Divider().padding(.leading, 52)

                    settingsRow(icon: "globe.badge.chevron.backward", title: "target_language_secondary", color: .green) {
                        Menu {
                            Button {
                                Task { await viewModel.setSecondaryTargetLanguageCode(nil, userChangedTarget: true) }
                            } label: {
                                Text("target_language_secondary_none")
                            }
                            Divider()
                            ForEach(TranslationTargetLanguageOptions.allCodes, id: \.self) { code in
                                if TranslationTargetLanguageOptions.normalizedCode(code)
                                    != TranslationTargetLanguageOptions.normalizedCode(viewModel.primaryTargetLanguageCode) {
                                    Button {
                                        Task { await viewModel.setSecondaryTargetLanguageCode(code, userChangedTarget: true) }
                                    } label: {
                                        Text(TranslationTargetLanguageOptions.displayName(code: code, locale: locale))
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                if let s = viewModel.secondaryTargetLanguageCode, !s.isEmpty {
                                    Text(labelForLanguage(code: s))
                                        .font(.subheadline)
                                } else {
                                    Text("target_language_secondary_none")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Divider().padding(.leading, 52)
                    
                    settingsRow(icon: "text.bubble", title: "translate_all_subtitles", color: .green) {
                        if viewModel.isTranslating {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Button("start_translation") {
                                Task { await viewModel.translateAllSegments() }
                            }
                            .font(.subheadline)
                            .foregroundStyle(.green)
                        }
                    }
                    
                    Divider().padding(.leading, 52)
                    
                    settingsToggleRow(
                        icon: "text.bubble.fill", title: "show_translation_primary",
                        subtitle: "show_translation_below_each_line", color: .green,
                        isOn: $viewModel.showPrimaryTranslation
                    )

                    if let s = viewModel.secondaryTargetLanguageCode, !s.isEmpty {
                        Divider().padding(.leading, 52)
                        settingsToggleRow(
                            icon: "text.bubble", title: "show_translation_secondary",
                            subtitle: "show_translation_below_each_line", color: .green,
                            isOn: $viewModel.showSecondaryTranslation
                        )
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
                .padding(.horizontal, 16)
            }
            
            VStack(spacing: 0) {
                Text("japanese_subtitles")
                    .font(.caption).fontWeight(.semibold).foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.bottom, 8)
                
                VStack(spacing: 0) {
                    settingsToggleRow(
                        icon: "character.textbox", title: "furigana",
                        subtitle: "show_furigana_above_text", color: .green,
                        isOn: $viewModel.showFurigana
                    )
                    Divider().padding(.leading, 52)
                    settingsToggleRow(
                        icon: "a.circle", title: "romaji",
                        subtitle: "show_romaji_below_text", color: .green,
                        isOn: $viewModel.showRomaji
                    )
                    Divider().padding(.leading, 52)
                    settingsToggleRow(
                        icon: "book.closed", title: "loanword_english",
                        subtitle: "show_english_above_katakana", color: .green,
                        isOn: $viewModel.showEnglish
                    )
                }
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
                .padding(.horizontal, 16)
            }
        }
        .padding(.top, 4)
    }
    
    private static let interSubtitlePauseChoices: [Double] = [0, 0.5, 1, 1.5, 2, 3]
    
    private var practiceReadingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("practice_reading_section")
                .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                .padding(.horizontal, 20)
            VStack(spacing: 0) {
                settingsRow(icon: "pause.circle", title: "inter_subtitle_pause_label", color: .green) {
                    Menu {
                        ForEach(Self.interSubtitlePauseChoices, id: \.self) { sec in
                            Button {
                                viewModel.setInterSubtitlePause(seconds: sec)
                            } label: {
                                Text(interSubtitlePauseChoiceLabel(seconds: sec))
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(interSubtitlePauseChoiceLabel(seconds: viewModel.interSubtitlePauseSeconds))
                                .font(.subheadline)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Divider().padding(.leading, 52)
                settingsToggleRow(
                    icon: "mic.circle",
                    title: "player_show_shadow_reading_mic",
                    subtitle: "player_show_shadow_reading_mic_subtitle",
                    color: .green,
                    isOn: $viewModel.showShadowReadingMic
                )
            }
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
            .padding(.horizontal, 16)
            Text("inter_subtitle_pause_hint")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 20)
        }
    }
    
    private func interSubtitlePauseChoiceLabel(seconds: Double) -> String {
        let c = Self.interSubtitlePauseChoices.min(by: { abs($0 - seconds) < abs($1 - seconds) }) ?? seconds
        if c == 0 {
            return String(localized: LocalizedStringResource("inter_subtitle_pause_none", locale: locale))
        }
        let fmt = String(localized: LocalizedStringResource("inter_subtitle_pause_seconds_format", locale: locale))
        let v = (c == floor(c)) ? String(Int(c)) : String(c)
        return String(format: fmt, v)
    }
    
    private func settingsRow<Content: View>(
        icon: String, title: LocalizedStringKey, color: Color,
        @ViewBuilder trailing: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.body).foregroundStyle(color).frame(width: 28)
            Text(title).font(.subheadline)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
    
    private func settingsToggleRow(
        icon: String, title: LocalizedStringKey, subtitle: LocalizedStringKey, color: Color,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.body).foregroundStyle(color).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().tint(.green)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func labelForLanguage(code: String) -> String {
        TranslationTargetLanguageOptions.displayName(code: code, locale: locale)
    }
}
