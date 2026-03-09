//
//  PlaybackControlsView.swift
//  YomiPlay
//
//  再生コントロールコンポーネント
//  進捗バー + 時間 + ボタンパネル
//

import SwiftUI

// MARK: - 再生コントロールビュー

struct PlaybackControlsView: View {
    let isPlaying: Bool
    let currentTime: TimeInterval
    let duration: TimeInterval
    let playbackRateText: String
    let isLooping: Bool
    let onTogglePlayPause: () -> Void
    let onSkipBackward: () -> Void
    let onSkipForward: () -> Void
    let onSeek: (TimeInterval) -> Void
    let onCycleRate: () -> Void
    let onToggleLoop: () -> Void
    
    @State private var isDragging = false
    @State private var dragValue: Double = 0
    
    var body: some View {
        VStack(spacing: 8) {
            // プログレスバー
            progressBar
            
            // 時間表示
            timeDisplay
            
            // コントロールボタン
            controlButtons
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemBackground).opacity(0.95))
    }
    
    // MARK: - プログレスバー
    
    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.systemGray5))
                    .frame(height: 4)
                
                Capsule()
                    .fill(Color.green)
                    .frame(
                        width: max(0, progressWidth(in: geometry.size.width)),
                        height: 4
                    )
                
                Circle()
                    .fill(Color.green)
                    .frame(width: isDragging ? 16 : 10, height: isDragging ? 16 : 10)
                    .offset(x: max(0, progressWidth(in: geometry.size.width) - 5))
            }
            .frame(height: 16)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        let progress = max(0, min(1, value.location.x / geometry.size.width))
                        dragValue = progress * duration
                    }
                    .onEnded { value in
                        isDragging = false
                        let progress = max(0, min(1, value.location.x / geometry.size.width))
                        onSeek(progress * duration)
                    }
            )
            .animation(.easeInOut(duration: 0.15), value: isDragging)
        }
        .frame(height: 16)
    }
    
    private func progressWidth(in totalWidth: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        let time = isDragging ? dragValue : currentTime
        return CGFloat(time / duration) * totalWidth
    }
    
    // MARK: - 時間表示
    
    private var timeDisplay: some View {
        HStack {
            Text(AudioPlayerService.formatTime(isDragging ? dragValue : currentTime))
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Text(AudioPlayerService.formatTime(duration))
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - コントロールボタン
    
    private var controlButtons: some View {
        HStack(spacing: 0) {
            // ループ
            controlButton(
                icon: isLooping ? "repeat.1" : "repeat",
                label: String(localized: "重复"),
                isActive: isLooping,
                action: onToggleLoop
            )
            
            Spacer()
            
            // 5秒戻る
            Button(action: onSkipBackward) {
                Image(systemName: "gobackward.5")
                    .font(.title3)
                    .foregroundStyle(.primary)
            }
            .frame(width: 44)
            
            Spacer()
            
            // 再生/一時停止
            Button(action: onTogglePlayPause) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .foregroundStyle(.primary)
                    .frame(width: 50, height: 50)
                    .background(
                        Circle()
                            .fill(Color.green.opacity(0.2))
                    )
            }
            
            Spacer()
            
            // 10秒進む
            Button(action: onSkipForward) {
                Image(systemName: "goforward.10")
                    .font(.title3)
                    .foregroundStyle(.primary)
            }
            .frame(width: 44)
            
            Spacer()
            
            // 速度
            controlButton(
                icon: "gauge.with.dots.needle.33percent",
                label: playbackRateText,
                isActive: false,
                action: onCycleRate
            )
        }
        .padding(.vertical, 4)
    }
    
    private func controlButton(icon: String, label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(isActive ? Color.green : .secondary)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(isActive ? Color.green : .secondary)
            }
        }
        .frame(width: 50)
    }
}

// MARK: - プレビュー

#Preview {
    PlaybackControlsView(
        isPlaying: false,
        currentTime: 35,
        duration: 182,
        playbackRateText: "1x",
        isLooping: false,
        onTogglePlayPause: {},
        onSkipBackward: {},
        onSkipForward: {},
        onSeek: { _ in },
        onCycleRate: {},
        onToggleLoop: {}
    )
    .preferredColorScheme(.dark)
}
