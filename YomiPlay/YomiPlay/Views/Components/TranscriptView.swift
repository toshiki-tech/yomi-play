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
    let fontSize: CGFloat
    let editingSegmentID: UUID?
    @Binding var editingText: String
    let onSegmentTapped: (TranscriptSegment) -> Void
    let onEditTapped: (TranscriptSegment) -> Void
    let onEditConfirmed: () -> Void
    let onEditCancelled: () -> Void
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(segments) { segment in
                        SegmentRowView(
                            segment: segment,
                            isActive: segment.id == currentSegmentID,
                            isEditing: editingSegmentID == segment.id,
                            showFurigana: showFurigana,
                            showRomaji: showRomaji,
                            fontSize: fontSize,
                            editingText: $editingText,
                            onTapped: { onSegmentTapped(segment) },
                            onEditTapped: { onEditTapped(segment) },
                            onEditConfirmed: onEditConfirmed,
                            onEditCancelled: onEditCancelled
                        )
                        .id(segment.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: currentSegmentID) { _, newID in
                if let id = newID, editingSegmentID == nil {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
            .onChange(of: editingSegmentID) { _, newID in
                if let id = newID {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
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
    let fontSize: CGFloat
    @Binding var editingText: String
    let onTapped: () -> Void
    let onEditTapped: () -> Void
    let onEditConfirmed: () -> Void
    let onEditCancelled: () -> Void
    
    @FocusState private var isFocused: Bool
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
            if !segment.tokens.isEmpty {
                FuriganaTextView(
                    tokens: segment.tokens,
                    showFurigana: showFurigana,
                    showRomaji: showRomaji,
                    fontSize: fontSize
                )
                .foregroundStyle(isActive ? .white : .primary)
            } else {
                Text(segment.originalText)
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundStyle(isActive ? .white : .primary)
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
            Text(formatTimeRange(start: segment.startTime, end: segment.endTime))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            
            TextField("字幕テキストを入力", text: $editingText, axis: .vertical)
                .font(.system(size: fontSize, weight: .medium))
                .textFieldStyle(.plain)
                .focused($isFocused)
                .lineLimit(1...5)
            
            HStack(spacing: 12) {
                Spacer()
                Button(action: onEditCancelled) {
                    Text("キャンセル")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color(.systemGray5)))
                }
                Button(action: onEditConfirmed) {
                    Text("確定")
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
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isFocused = true
            }
        }
    }
    
    private func formatTimeRange(start: TimeInterval, end: TimeInterval) -> String {
        let startStr = AudioPlayerService.formatTime(start)
        let endStr = AudioPlayerService.formatTime(end)
        return "\(startStr) - \(endStr)"
    }
}
