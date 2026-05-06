//
//  TranscriptView.swift
//  YomiPlay
//
//  字幕リストコンポーネント
//

import SwiftUI
import UIKit

struct TranscriptView: View {
    let segments: [TranscriptSegment]
    let currentSegmentID: UUID?
    /// 当前播放时间（秒），用于当前行卡拉OK 逐词高亮
    let currentTime: TimeInterval
    let showFurigana: Bool
    let showRomaji: Bool
    let showEnglish: Bool
    let showTranslation: Bool
    let fontSize: CGFloat
    let editingSegmentID: UUID?
    @Binding var editingText: String
    @Binding var editingTranslatedText: String?
    @Binding var editingTokenReadings: [EditableTokenReading]
    @Binding var editingTokenSegmentationText: String
    @Binding var editingSkipFurigana: Bool
    @Binding var editingStartTime: TimeInterval
    @Binding var editingEndTime: TimeInterval
    let isTranslating: Bool
    /// 是否在每行字幕旁显示跟读麦克风（播放页设置）
    let showShadowReadingMic: Bool
    let onSegmentTapped: (TranscriptSegment) -> Void
    let onEditTapped: (TranscriptSegment) -> Void
    let onEditConfirmed: () -> Void
    let onEditCancelled: () -> Void
    let onDeleteSegment: () -> Void
    let onSplitSegment: () -> Void
    let onMergeWithPrevious: () -> Void
    let onApplyManualSegmentation: () -> Void
    let onTranslateThisSegment: () async -> Void
    let onShadowReadingTapped: (TranscriptSegment) -> Void

    @FocusState private var focusedSegmentID: UUID?
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                        SegmentRowView(
                            segment: segment,
                            isActive: segment.id == currentSegmentID,
                            currentTime: currentTime,
                            isEditing: editingSegmentID == segment.id,
                            showFurigana: showFurigana,
                            showRomaji: showRomaji,
                            showEnglish: showEnglish,
                            showTranslation: showTranslation,
                            fontSize: fontSize,
                            editingText: $editingText,
                            editingTranslatedText: $editingTranslatedText,
                            editingTokenReadings: $editingTokenReadings,
                            editingTokenSegmentationText: $editingTokenSegmentationText,
                            editingSkipFurigana: $editingSkipFurigana,
                            editingStartTime: $editingStartTime,
                            editingEndTime: $editingEndTime,
                            isTranslating: isTranslating,
                            focusedSegmentID: $focusedSegmentID,
                            onTapped: { onSegmentTapped(segment) },
                            onEditTapped: { onEditTapped(segment) },
                            onEditConfirmed: onEditConfirmed,
                            onEditCancelled: onEditCancelled,
                            onDeleteSegment: onDeleteSegment,
                            onSplitSegment: onSplitSegment,
                            onMergeWithPrevious: onMergeWithPrevious,
                            onApplyManualSegmentation: onApplyManualSegmentation,
                            onTranslateThisSegment: onTranslateThisSegment,
                            onShadowReadingTapped: { onShadowReadingTapped(segment) },
                            showShadowReadingMic: showShadowReadingMic,
                            canMergeWithPrevious: index > 0
                        )
                        .id(segment.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.never)
            .onChange(of: currentSegmentID) { _, newID in
                if let id = newID, editingSegmentID == nil {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
            .onChange(of: editingSegmentID) { _, newID in
                if let id = newID {
                    // 編集開始時にスクロールとフォーカスを制御
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                    // アニメーション完了を待たずに早めにフォーカスを当てる
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        focusedSegmentID = id
                    }
                } else {
                    focusedSegmentID = nil
                }
            }
        }
    }
}

// MARK: - 各行のビュー（表示モードと編集モードを同一ビュー内で切り替え）

struct SegmentRowView: View {
    @Environment(\.locale) private var locale
    @Environment(\.playerThemeScheme) private var playerScheme
    let segment: TranscriptSegment
    let isActive: Bool
    let currentTime: TimeInterval
    let isEditing: Bool
    let showFurigana: Bool
    
    private var palette: PlayerPalette { PlayerTheme.palette(for: playerScheme) }
    let showRomaji: Bool
    let showEnglish: Bool
    let showTranslation: Bool
    let fontSize: CGFloat
    @Binding var editingText: String
    @Binding var editingTranslatedText: String?
    @Binding var editingTokenReadings: [EditableTokenReading]
    @Binding var editingTokenSegmentationText: String
    @Binding var editingSkipFurigana: Bool
    @Binding var editingStartTime: TimeInterval
    @Binding var editingEndTime: TimeInterval
    let isTranslating: Bool
    var focusedSegmentID: FocusState<UUID?>.Binding
    let onTapped: () -> Void
    let onEditTapped: () -> Void
    let onEditConfirmed: () -> Void
    let onEditCancelled: () -> Void
    let onDeleteSegment: () -> Void
    let onSplitSegment: () -> Void
    let onMergeWithPrevious: () -> Void
    let onApplyManualSegmentation: () -> Void
    let onTranslateThisSegment: () async -> Void
    let onShadowReadingTapped: () -> Void
    let showShadowReadingMic: Bool
    let canMergeWithPrevious: Bool
    
    @State private var isLongPressing = false
    @State private var showFuriganaEditor = false

    /// 非日语句子不提供注音编辑入口，避免无效操作与认知负担。
    private var shouldShowFuriganaEditorButton: Bool {
        if let code = segment.originalTextLanguageCode?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !code.isEmpty {
            return code == "ja" || code.hasPrefix("ja-")
        }
        if segment.skipFurigana {
            return WhisperSpeechRecognitionService.isLikelyJapanese(segment.originalText)
        }
        return true
    }
    
    var body: some View {
        Group {
            if isEditing {
                editingBody
            } else {
                displayBody
            }
        }
    }
    
    // MARK: - 表示モード
    
    private var displayBody: some View {
        let explicitTokens = segment.userTokenOverrides ?? segment.tokens
        let displayTokens = resolvedDisplayTokens(from: explicitTokens)
        return HStack(alignment: .top, spacing: 10) {
        VStack(alignment: .leading, spacing: 6) {
            // 上段：原文 + 卡拉 OK 高亮
            if !displayTokens.isEmpty {
                if segment.skipFurigana {
                    // 非日语或关闭假名时：使用简化版卡拉 OK 文本（按 word 时间高亮）
                    PlainKaraokeTextView(
                        tokens: displayTokens,
                        fontSize: fontSize,
                        currentTime: isActive ? currentTime : nil,
                        segmentStart: segment.startTime,
                        segmentEnd: segment.endTime,
                        palette: palette
                    )
                } else {
                    // 日语：带振假名/罗马字/词性着色的高级视图
                    FuriganaTextView(
                        tokens: displayTokens,
                        showFurigana: showFurigana,
                        showRomaji: showRomaji,
                        showEnglish: showEnglish,
                        fontSize: fontSize,
                        currentTime: isActive ? currentTime : nil,
                        segmentStart: segment.startTime,
                        segmentEnd: segment.endTime
                    )
                    .foregroundStyle(isActive ? palette.contentForegroundActive : .primary)
                }
            } else {
                Text(segment.originalText)
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundStyle(isActive ? palette.contentForegroundActive : .primary)
            }
            
            // 下段：翻译文本
            if showTranslation,
               let translated = segment.translatedText,
               !translated.isEmpty {
                Text(translated)
                    .font(.system(size: fontSize * 0.85))
                    .foregroundStyle(isActive ? palette.contentForegroundActiveSecondary : .secondary)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            onTapped()
        }
        .onLongPressGesture(minimumDuration: 0.4, pressing: { pressing in
            isLongPressing = pressing
        }, perform: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onEditTapped()
        })

            if showShadowReadingMic {
                Button {
                    onShadowReadingTapped()
                } label: {
                    Image(systemName: "mic.circle")
                        .font(.title2)
                        .foregroundStyle(isActive ? palette.accent : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: LocalizedStringResource("shadow_reading_mic_a11y", locale: locale)))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isLongPressing
                      ? palette.segmentPressedBackground
                      : (isActive ? palette.segmentActiveBackground : Color(.secondarySystemBackground)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isActive ? palette.segmentActiveBorder : Color.clear, lineWidth: 1)
        )
        .scaleEffect(isLongPressing ? 0.97 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isLongPressing)
    }

    /// 非日语句子在部分历史数据/导入路径下可能没有 token，兜底按文本切分，保证卡拉OK高亮始终可用。
    private func resolvedDisplayTokens(from explicitTokens: [FuriganaToken]) -> [FuriganaToken] {
        if !explicitTokens.isEmpty {
            return explicitTokens
        }
        guard segment.skipFurigana else {
            return []
        }
        return fallbackPlainTokens(for: segment.originalText)
    }

    /// 优先按空白分词（英文等），若无空白则按字符切分（中文等），并忽略纯空白 token。
    private func fallbackPlainTokens(for text: String) -> [FuriganaToken] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if trimmed.contains(where: \.isWhitespace) {
            return trimmed
                .split(whereSeparator: \.isWhitespace)
                .map { part in
                    FuriganaToken(surface: String(part))
                }
        }

        return trimmed.compactMap { ch in
            let token = String(ch)
            return token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : FuriganaToken(surface: token)
        }
    }
    
    // MARK: - 編集モード
    
    private var editingBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Start")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Button {
                            editingStartTime = max(0, editingStartTime - 0.1)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(AudioPlayerService.formatTime(editingStartTime))
                            .font(.caption2)
                            .monospacedDigit()
                        Button {
                            editingStartTime += 0.1
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("End")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Button {
                            editingEndTime = max(0, editingEndTime - 0.1)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(AudioPlayerService.formatTime(editingEndTime))
                            .font(.caption2)
                            .monospacedDigit()
                        Button {
                            editingEndTime += 0.1
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            
            TextField("enter_subtitle_text", text: $editingText, axis: .vertical)
                .font(.system(size: fontSize, weight: .medium))
                .textFieldStyle(.plain)
                .focused(focusedSegmentID, equals: segment.id)
                .lineLimit(1...5)
            
            Toggle(isOn: $editingSkipFurigana) {
                HStack(spacing: 6) {
                    Image(systemName: editingSkipFurigana ? "textformat.alt" : "character.textbox")
                        .font(.caption)
                        .foregroundStyle(editingSkipFurigana ? .orange : .secondary)
                    Text("non_japanese_no_furigana")
                        .font(.caption)
                        .foregroundStyle(editingSkipFurigana ? .orange : .secondary)
                }
            }
            .toggleStyle(.switch)
            .tint(.orange)

            if shouldShowFuriganaEditorButton {
                Button {
                    showFuriganaEditor = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "character.book.closed")
                        Text("pronunciation_editor_open")
                            .font(.caption)
                    }
                    .foregroundStyle(palette.accent)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("translation_editable_label")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                TextField("translation_edit_placeholder", text: Binding(
                    get: { editingTranslatedText ?? "" },
                    set: { editingTranslatedText = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
                ), axis: .vertical)
                    .font(.system(size: fontSize * 0.9))
                    .textFieldStyle(.plain)
                    .lineLimit(2...4)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemBackground)))
            }
            Button {
                Task { await onTranslateThisSegment() }
            } label: {
                HStack(spacing: 6) {
                    if isTranslating && isEditing {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "text.bubble")
                            .font(.caption)
                    }
                    Text("translate_this_segment")
                        .font(.caption)
                }
                .foregroundStyle(palette.accent)
            }
            .disabled(editingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTranslating)
            
            HStack(spacing: 12) {
                Button(role: .destructive, action: onDeleteSegment) {
                    Text("delete")
                        .font(.caption)
                }
                Spacer()
                Button(action: onSplitSegment) {
                    Text("split_segment")
                        .font(.caption)
                }
                Button(action: onMergeWithPrevious) {
                    Text("merge_with_previous")
                        .font(.caption)
                }
                .disabled(!canMergeWithPrevious)
                Button(action: onEditCancelled) {
                    Text("cancel")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color(.systemGray5)))
                }
                Button(action: onEditConfirmed) {
                    Text("confirm")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(palette.accent))
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(palette.accent, lineWidth: 2))
        .onTapGesture {
            // 背景タップでも確実にフォーカスを当てる（キーボード表示用）
            focusedSegmentID.wrappedValue = segment.id
        }
        .sheet(isPresented: $showFuriganaEditor) {
            FuriganaEditorSheet(
                editingTokenReadings: $editingTokenReadings,
                editingTokenSegmentationText: $editingTokenSegmentationText,
                onApplySegmentation: onApplyManualSegmentation
            )
        }
    }
}

private struct FuriganaEditorSheet: View {
    @Binding var editingTokenReadings: [EditableTokenReading]
    @Binding var editingTokenSegmentationText: String
    let onApplySegmentation: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("pronunciation_editor_segmentation_hint")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(
                        "pronunciation_editor_segmentation_placeholder",
                        text: $editingTokenSegmentationText,
                        axis: .vertical
                    )
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                    Button("pronunciation_editor_apply_segmentation") {
                        onApplySegmentation()
                    }
                    .buttonStyle(.borderedProminent)

                    if !editingTokenReadings.isEmpty {
                        ForEach(editingTokenReadings) { item in
                            if let itemBinding = bindingForItem(id: item.id) {
                                EditableTokenReadingRow(item: itemBinding)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("pronunciation_editor_title")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("done") { dismiss() }
                }
            }
        }
    }

    private func bindingForItem(id: UUID) -> Binding<EditableTokenReading>? {
        guard let current = editingTokenReadings.first(where: { $0.id == id }) else { return nil }
        return Binding(
            get: {
                editingTokenReadings.first(where: { $0.id == id }) ?? current
            },
            set: { updated in
                guard let idx = editingTokenReadings.firstIndex(where: { $0.id == id }) else { return }
                editingTokenReadings[idx] = updated
            }
        )
    }
}

private struct EditableTokenReadingRow: View {
    @Binding var item: EditableTokenReading

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.surface)
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("reading", text: $item.reading)
                .textFieldStyle(.roundedBorder)

            TextField("romaji", text: $item.romaji)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)

            Toggle(isOn: Binding(
                get: { item.englishMeaningEnabled },
                set: { enabled in
                    item.englishMeaningEnabled = enabled
                    if !enabled {
                        item.englishMeaning = nil
                    }
                }
            )) {
                Text("pronunciation_editor_english_meaning")
                    .font(.caption)
            }
            .toggleStyle(.switch)
            .tint(.blue)

            if item.englishMeaningEnabled {
                TextField("pronunciation_editor_english_meaning_placeholder", text: Binding(
                    get: { item.englishMeaning ?? "" },
                    set: { newValue in
                        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        item.englishMeaning = trimmed.isEmpty ? nil : trimmed
                    }
                ))
                .textFieldStyle(.roundedBorder)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemBackground)))
    }
}
