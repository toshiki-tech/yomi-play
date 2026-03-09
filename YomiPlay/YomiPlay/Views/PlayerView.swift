//
//  PlayerView.swift
//  YomiPlay
//
//  プレーヤー画面
//  字幕表示 + 再生コントロール + 設定シート + 字幕編集
//

import SwiftUI
import Translation

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
        .navigationTitle(document.source.title.isEmpty ? "再生中" : document.source.title)
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
                        Text("ホーム")
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
    
    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("通用").tag(0)
                Text("学習特性").tag(1)
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
            settingsRow(icon: "textformat.size", title: "字体大小", color: .green) {
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
            
            settingsRow(icon: "gauge.with.dots.needle.33percent", title: "播放速度", color: .green) {
                Text(viewModel.playbackRateText)
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            
            Divider().padding(.leading, 52)
            
            settingsRow(icon: "square.and.arrow.up", title: "导出字幕 SRT", color: .green) {
                Button("导出") {
                    if let url = SubtitleExportService.writeSRTToTempFile(
                        segments: viewModel.document.segments,
                        fileName: viewModel.document.source.title
                    ) {
                        srtExportItem = IdentifiableURL(url: url)
                    }
                }
                .font(.subheadline).foregroundStyle(.green)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .padding(.horizontal, 16)
        .sheet(item: $srtExportItem) { item in
            NavigationStack {
                VStack(spacing: 20) {
                    ShareLink(item: item.url, preview: SharePreview("字幕.srt", image: Image(systemName: "doc.text")))
                        .font(.headline)
                    Button("閉じる") { srtExportItem = nil }
                        .foregroundStyle(.secondary)
                }
                .padding()
                .navigationTitle("字幕を共有")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
    
    private var learningSettings: some View {
        VStack(spacing: 16) {
            VStack(spacing: 0) {
                Text("日语字幕")
                    .font(.caption).fontWeight(.semibold).foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.bottom, 8)
                
                VStack(spacing: 0) {
                    settingsToggleRow(
                        icon: "character.textbox", title: "振假名",
                        subtitle: "在顶部显示振假名", color: .green,
                        isOn: $viewModel.showFurigana
                    )
                    Divider().padding(.leading, 52)
                    settingsToggleRow(
                        icon: "a.circle", title: "罗马字",
                        subtitle: "在底部显示罗马字", color: .green,
                        isOn: $viewModel.showRomaji
                    )
                    Divider().padding(.leading, 52)
                    settingsToggleRow(
                        icon: "book.closed", title: "外来词英文",
                        subtitle: "在片假名上方显示英文原词", color: .green,
                        isOn: $viewModel.showEnglish
                    )
                }
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
                .padding(.horizontal, 16)
            }
            
            VStack(spacing: 0) {
                Text("翻译")
                    .font(.caption).fontWeight(.semibold).foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.bottom, 8)
                
                VStack(spacing: 0) {
                    settingsRow(icon: "globe", title: "目标语言", color: .green) {
                        Menu {
                            Button("中文（简体）") { viewModel.targetLanguageCode = "zh-Hans" }
                            Button("中文（繁体）") { viewModel.targetLanguageCode = "zh-Hant" }
                            Button("English") { viewModel.targetLanguageCode = "en" }
                            Button("한국어") { viewModel.targetLanguageCode = "ko" }
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
                    
                    settingsRow(icon: "text.bubble", title: "翻译全部字幕", color: .green) {
                        if viewModel.isTranslating {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Button("开始翻译") {
                                viewModel.requestTranslation()
                            }
                            .font(.subheadline)
                            .foregroundStyle(.green)
                        }
                    }
                    
                    Divider().padding(.leading, 52)
                    
                    settingsToggleRow(
                        icon: "text.bubble.fill", title: "显示翻译",
                        subtitle: "在每行日语下面显示翻译", color: .green,
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
        icon: String, title: String, color: Color,
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
        icon: String, title: String, subtitle: String, color: Color,
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
        case "zh-Hans": return "中文（简体）"
        case "zh-Hant": return "中文（繁体）"
        case "en": return "English"
        case "ko": return "한국어"
        default: return code
        }
    }
}
