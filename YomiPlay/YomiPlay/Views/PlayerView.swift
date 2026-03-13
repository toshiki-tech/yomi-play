//
//  PlayerView.swift
//  YomiPlay
//
//  プレーヤー画面
//  字幕表示 + 再生コントロール + 設定シート + 字幕編集
//

import SwiftUI
import Translation
import UniformTypeIdentifiers

// MARK: - プレーヤー画面

struct PlayerView: View {
    @Binding var navigationPath: NavigationPath
    @State private var viewModel: PlayerViewModel
    @State private var playlist: [TranscriptDocument]
    @State private var currentIndex: Int
    @State private var showSettings: Bool = false
    @State private var shouldAutoPlayOnReady: Bool = false
    @Environment(\.dismiss) private var dismiss
    
    init(documents: [TranscriptDocument], currentIndex: Int, navigationPath: Binding<NavigationPath>) {
        let safeIndex = max(0, min(documents.count - 1, currentIndex))
        let initialDocument = documents.isEmpty ? TranscriptDocument(source: AudioSource(type: .local, title: "")) : documents[safeIndex]
        self._navigationPath = navigationPath
        self._viewModel = State(initialValue: PlayerViewModel(document: initialDocument))
        self._playlist = State(initialValue: documents.isEmpty ? [initialDocument] : documents)
        self._currentIndex = State(initialValue: safeIndex)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 字幕エリア
            transcriptSection
            
            Divider()
                .overlay(Color(.systemGray4))
            
            // 再生コントロール
            controlsSection
        }
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
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
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
                playNextIfAvailable()
            }
        }
        .translationTask(viewModel.translationConfiguration) { session in
            await viewModel.performTranslation(using: session)
        }
    }
    
    // MARK: - 字幕セクション
    
    private var transcriptSection: some View {
        TranscriptView(
            segments: viewModel.document.segments,
            currentSegmentID: viewModel.playerService.currentSegmentID,
            showFurigana: viewModel.showFurigana,
            showRomaji: viewModel.showRomaji,
            showEnglish: viewModel.showEnglish,
            showTranslation: viewModel.showTranslation,
            fontSize: viewModel.fontSize,
            editingSegmentID: viewModel.editingSegmentID,
            editingText: $viewModel.editingText,
            editingSkipFurigana: $viewModel.editingSkipFurigana,
            editingStartTime: $viewModel.editingStartTime,
            editingEndTime: $viewModel.editingEndTime,
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
            isLooping: viewModel.isLooping,
            onTogglePlayPause: { viewModel.togglePlayPause() },
            onSkipBackward: { viewModel.skipBackward() },
            onSkipForward: { viewModel.skipForward() },
            onSeek: { time in viewModel.seek(to: time) },
            onCycleRate: { viewModel.cyclePlaybackRate() },
            onToggleLoop: { viewModel.toggleCurrentLoop() }
        )
    }
    
    // MARK: - プレイリスト制御
    
    private func playNextIfAvailable() {
        let nextIndex = currentIndex + 1
        guard nextIndex < playlist.count else { return }
        let nextDocument = playlist[nextIndex]
        currentIndex = nextIndex
        viewModel = PlayerViewModel(document: nextDocument)
        shouldAutoPlayOnReady = true
        // onPlaybackEnded ハンドラを新しいプレイヤーに再設定
        viewModel.playerService.onPlaybackEnded = {
            playNextIfAvailable()
        }
    }
}

// MARK: - 共有用の URL ラッパー（Identifiable）

private struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - 設定シートビュー

struct SettingsSheetView: View {
    @Bindable var viewModel: PlayerViewModel
    @State private var selectedTab = 0
    @State private var srtExportItem: IdentifiableURL?
    @State private var yomiExportItem: IdentifiableURL?
    @State private var audioExportItem: IdentifiableURL?
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
                learningSettings
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
        .sheet(item: $srtExportItem) { item in
            NavigationStack {
                VStack(spacing: 24) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(.blue)
                    
                    VStack(spacing: 4) {
                        Text("export_subtitles_srt")
                            .font(.headline)
                        Text(item.url.lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    
                    ShareLink(item: item.url, preview: SharePreview(Text("srt"), image: Image(systemName: "doc.text"))) {
                        Label("share_subtitles", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("close") {
                        srtExportItem = nil
                        hasExportedSRT = true
                    }
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
                .navigationTitle("share_subtitles")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(item: $yomiExportItem) { item in
            NavigationStack {
                VStack(spacing: 24) {
                    Image("yomi-mark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    VStack(spacing: 4) {
                        Text("player_export_yomi_title")
                            .font(.headline)
                        Text(item.url.lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("full_subtitle_file_with_furigana_translations_etc")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    ShareLink(item: item.url, preview: SharePreview("YomiPlay", image: Image("yomi-mark"))) {
                        Label("share_subtitles", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("close") {
                        yomiExportItem = nil
                        hasExportedYomi = true
                    }
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
                .navigationTitle(String(localized: "player_share_yomi_title"))
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(item: $audioExportItem) { item in
            NavigationStack {
                VStack(spacing: 24) {
                    Image(systemName: "waveform")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(.green)
                    
                    VStack(spacing: 4) {
                        Text("settings_export_media_title")
                            .font(.headline)
                        Text(item.url.lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    
                    ShareLink(item: item.url, preview: SharePreview(viewModel.document.source.title, image: Image(systemName: "waveform"))) {
                        Label("share_subtitles", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("close") {
                        audioExportItem = nil
                        hasExportedAudio = true
                    }
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
                .navigationTitle("settings_share_audio_title")
                .navigationBarTitleDisplayMode(.inline)
            }
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
                        switch type {
                        case "SRT": srtExportItem = IdentifiableURL(url: url)
                        case "YOMI": yomiExportItem = IdentifiableURL(url: url)
                        default: audioExportItem = IdentifiableURL(url: url)
                        }
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
                        .font(.subheadline).monospacedDigit().frame(width: 32)
                    
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
            
            VStack(spacing: 0) {
                Text("translation")
                    .font(.caption).fontWeight(.semibold).foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.bottom, 8)
                
                VStack(spacing: 0) {
                    settingsRow(icon: "globe", title: "target_language", color: .green) {
                        Menu {
                            Button("chinese_simplified") { viewModel.targetLanguageCode = "zh-Hans" }
                            Button("chinese_traditional") { viewModel.targetLanguageCode = "zh-Hant" }
                            Button("english") { viewModel.targetLanguageCode = "en" }
                        } label: {
                            HStack(spacing: 4) {
                                Text(labelForLanguage(code: viewModel.targetLanguageCode))
                                    .font(.subheadline)
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
                                viewModel.requestTranslation()
                            }
                            .font(.subheadline)
                            .foregroundStyle(.green)
                        }
                    }
                    
                    Divider().padding(.leading, 52)
                    
                    settingsToggleRow(
                        icon: "text.bubble.fill", title: "show_translation",
                        subtitle: "show_translation_below_each_line", color: .green,
                        isOn: $viewModel.showTranslation
                    )
                }
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
                .padding(.horizontal, 16)
            }
        }
        .padding(.top, 4)
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
        switch code {
        case "zh-Hans": return String(localized: "chinese_simplified")
        case "zh-Hant": return String(localized: "chinese_traditional")
        case "en": return String(localized: "english")
        default: return code
        }
    }
}
