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
    let showFurigana: Bool
    let showRomaji: Bool
    let showEnglish: Bool
    let showTranslation: Bool
    let fontSize: CGFloat
    let editingSegmentID: UUID?
    @Binding var editingText: String
    @Binding var editingTranslatedText: String?
    @Binding var editingSkipFurigana: Bool
    @Binding var editingStartTime: TimeInterval
    @Binding var editingEndTime: TimeInterval
    let isTranslating: Bool
    let onSegmentTapped: (TranscriptSegment) -> Void
    let onEditTapped: (TranscriptSegment) -> Void
    let onEditConfirmed: () -> Void
    let onEditCancelled: () -> Void
    let onDeleteSegment: () -> Void
    let onSplitSegment: () -> Void
    let onMergeWithPrevious: () -> Void
    let onTranslateThisSegment: () async -> Void

    @FocusState private var focusedSegmentID: UUID?
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                        SegmentRowView(
                            segment: segment,
                            isActive: segment.id == currentSegmentID,
                            isEditing: editingSegmentID == segment.id,
                            showFurigana: showFurigana,
                            showRomaji: showRomaji,
                            showEnglish: showEnglish,
                            showTranslation: showTranslation,
                            fontSize: fontSize,
                            editingText: $editingText,
                            editingTranslatedText: $editingTranslatedText,
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
                            onTranslateThisSegment: onTranslateThisSegment,
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
    let segment: TranscriptSegment
    let isActive: Bool
    let isEditing: Bool
    let showFurigana: Bool
    let showRomaji: Bool
    let showEnglish: Bool
    let showTranslation: Bool
    let fontSize: CGFloat
    @Binding var editingText: String
    @Binding var editingTranslatedText: String?
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
    let onTranslateThisSegment: () async -> Void
    let canMergeWithPrevious: Bool
    
    @State private var isLongPressing = false
    
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
        VStack(alignment: .leading, spacing: 6) {
            // 上段：原文（日语）＋振假名/罗马字/英语外来词
            if segment.skipFurigana {
                Text(segment.originalText)
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundStyle(isActive ? .white : .primary)
            } else if !segment.tokens.isEmpty {
                FuriganaTextView(
                    tokens: segment.tokens,
                    showFurigana: showFurigana,
                    showRomaji: showRomaji,
                    showEnglish: showEnglish,
                    fontSize: fontSize
                )
                .foregroundStyle(isActive ? .white : .primary)
            } else {
                Text(segment.originalText)
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundStyle(isActive ? .white : .primary)
            }
            
            // 下段：翻译文本
            if showTranslation,
               let translated = segment.translatedText,
               !translated.isEmpty {
                Text(translated)
                    .font(.system(size: fontSize * 0.85))
                    .foregroundStyle(isActive ? Color.white.opacity(0.9) : .secondary)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isLongPressing
                      ? Color.green.opacity(0.2)
                      : (isActive ? Color.green.opacity(0.3) : Color(.secondarySystemBackground)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isActive ? Color.green.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        .scaleEffect(isLongPressing ? 0.97 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isLongPressing)
        .onTapGesture {
            onTapped()
        }
        .onLongPressGesture(minimumDuration: 0.4, pressing: { pressing in
            isLongPressing = pressing
        }, perform: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onEditTapped()
        })
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
                .foregroundStyle(.green)
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
                        .background(Capsule().fill(Color.green))
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.green, lineWidth: 2))
        .onTapGesture {
            // 背景タップでも確実にフォーカスを当てる（キーボード表示用）
            focusedSegmentID.wrappedValue = segment.id
        }
    }
}
