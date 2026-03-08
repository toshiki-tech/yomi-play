//
//  TranscriptView.swift
//  YomiPlay
//
//  字幕リストコンポーネント
//

import SwiftUI

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
                        if editingSegmentID == segment.id {
                            EditingRowView(
                                segment: segment,
                                editingText: $editingText,
                                fontSize: fontSize,
                                onConfirm: onEditConfirmed,
                                onCancel: onEditCancelled
                            )
                            .id(segment.id)
                        } else {
                            TranscriptRowView(
                                segment: segment,
                                isActive: segment.id == currentSegmentID,
                                showFurigana: showFurigana,
                                showRomaji: showRomaji,
                                fontSize: fontSize,
                                onTapped: { onSegmentTapped(segment) },
                                onEditTapped: { onEditTapped(segment) }
                            )
                            .id(segment.id)
                        }
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
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }
}

struct TranscriptRowView: View {
    let segment: TranscriptSegment
    let isActive: Bool
    let showFurigana: Bool
    let showRomaji: Bool
    let fontSize: CGFloat
    let onTapped: () -> Void
    let onEditTapped: () -> Void
    
    var body: some View {
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
                .fill(isActive ? Color.green.opacity(0.3) : Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isActive ? Color.green.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        .onTapGesture { onTapped() }
        .highPriorityGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in onEditTapped() }
        )
        .contextMenu {
            Button {
                // 等 context menu 关闭后再切到编辑状态，避免焦点/层级冲突
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    onEditTapped()
                }
            } label: {
                Label("編集", systemImage: "pencil")
            }
        }
    }
}

struct EditingRowView: View {
    let segment: TranscriptSegment
    @Binding var editingText: String
    let fontSize: CGFloat
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
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
                Button(action: onCancel) {
                    Text("キャンセル")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color(.systemGray5)))
                }
                Button(action: onConfirm) {
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
            // 从 context menu 进入时，等菜单完全消失后再唤起键盘，否则焦点会失效
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 400_000_000)
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
