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
    let document: TranscriptDocument
    @Binding var navigationPath: NavigationPath
    @State private var viewModel: PlayerViewModel
    @State private var showSettings: Bool = false
    @State private var hasRestoredPosition: Bool = false
    
    init(document: TranscriptDocument, navigationPath: Binding<NavigationPath>) {
        self.document = document
        self._navigationPath = navigationPath
        self._viewModel = State(initialValue: PlayerViewModel(document: document))
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
        .navigationTitle(document.source.title.isEmpty ? String(localized: "now_playing") : document.source.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    viewModel.playerService.pause()
                    navigationPath.removeLast()
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
            guard ready, !hasRestoredPosition else { return }
            hasRestoredPosition = true
            if let pos = viewModel.document.lastPlaybackPosition, pos > 0 {
                viewModel.seek(to: pos)
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
            }
        )
    }
    
    // MARK: - 再生コントロール
    
    private var controlsSection: some View {
        PlaybackControlsView(
            isPlaying: viewModel.isPlaying,
            currentTime: viewModel.playerService.currentTime,
            duration: viewModel.playerService.duration,
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
    
    enum ImportMode { case srt, yomi }
    @State private var importMode: ImportMode = .srt
    
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
                generalSettings
            } else {
                learningSettings
            }
            
            Spacer()
        }
        .background(Color(.systemGroupedBackground))
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
                        .font(.subheadline).monospacedDigit().frame(width: 28)
                    
                    Button { viewModel.adjustFontSize(by: 2) } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3).foregroundStyle(.green)
                    }.disabled(viewModel.fontSize >= 32)
                }
            }
            
            Divider().padding(.leading, 52)
            
            settingsRow(icon: "gauge.with.dots.needle.33percent", title: "playback_speed", color: .green) {
                Text(viewModel.playbackRateText)
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            
            Divider().padding(.leading, 52)
            
            settingsRow(icon: "waveform", title: "导出音频", color: .green) {
                if let url = viewModel.document.source.playbackURL {
                    Button("export") {
                        audioExportItem = IdentifiableURL(url: url)
                    }
                    .font(.subheadline).foregroundStyle(.green)
                } else {
                    Text("无音频文件")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            
            Divider().padding(.leading, 52)
            
            settingsRow(icon: "square.and.arrow.up", title: "export_subtitles_srt", color: .green) {
                Button("export") {
                    if let url = SubtitleExportService.writeSRTToTempFile(
                        segments: viewModel.document.segments,
                        fileName: viewModel.document.source.title
                    ) {
                        srtExportItem = IdentifiableURL(url: url)
                    }
                }
                .font(.subheadline).foregroundStyle(.green)
            }
            
            Divider().padding(.leading, 52)
            
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
            
            settingsRow(icon: "square.and.arrow.up.fill", title: "player_export_yomi_title", color: .green) {
                Button("export") {
                    if let url = SubtitleExportService.writeYomiToTempFile(
                        document: viewModel.document,
                        fileName: viewModel.document.source.title
                    ) {
                        yomiExportItem = IdentifiableURL(url: url)
                    }
                }
                .font(.subheadline).foregroundStyle(.green)
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
                VStack(spacing: 20) {
                    ShareLink(item: item.url, preview: SharePreview(Text("srt"), image: Image(systemName: "doc.text")))
                        .font(.headline)
                    Button("close") { srtExportItem = nil }
                        .foregroundStyle(.secondary)
                }
                .padding()
                .navigationTitle("share_subtitles")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(item: $yomiExportItem) { item in
            NavigationStack {
                VStack(spacing: 20) {
                    ShareLink(item: item.url, preview: SharePreview("YomiPlay", image: Image(systemName: "doc.text.fill")))
                        .font(.headline)
                    Text("full_subtitle_file_with_furigana_translations_etc")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("close") { yomiExportItem = nil }
                        .foregroundStyle(.secondary)
                }
                .padding()
                .navigationTitle(String(localized: "player_share_yomi_title"))
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(item: $audioExportItem) { item in
            NavigationStack {
                VStack(spacing: 20) {
                    ShareLink(item: item.url, preview: SharePreview(viewModel.document.source.title, image: Image(systemName: "waveform")))
                        .font(.headline)
                    Button("close") { audioExportItem = nil }
                        .foregroundStyle(.secondary)
                }
                .padding()
                .navigationTitle("分享音频")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
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
