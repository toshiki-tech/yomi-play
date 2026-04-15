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
    @Environment(\.playerThemeScheme) private var playerScheme
    /// 与设置里的「界面语言」一致；勿用裸 `String(localized:)`，否则会始终跟系统 Bundle 语言走
    @Environment(\.locale) private var locale
    let isPlaying: Bool
    let currentTime: TimeInterval
    let duration: TimeInterval
    let playbackRateText: String
    let playbackRate: Float
    let availablePlaybackRates: [Float]
    let repeatMode: PlaybackRepeatMode
    
    private var palette: PlayerPalette { PlayerTheme.palette(for: playerScheme) }
    let onTogglePlayPause: () -> Void
    let onSkipBackward: () -> Void
    let onSkipForward: () -> Void
    let onSeek: (TimeInterval) -> Void
    let onCycleRate: () -> Void
    let onSelectRate: (Float) -> Void
    let onSelectRepeatMode: (PlaybackRepeatMode) -> Void
    let onCycleRepeatMode: () -> Void
    
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
                    .fill(palette.accent)
                    .frame(
                        width: max(0, progressWidth(in: geometry.size.width)),
                        height: 4
                    )
                
                Circle()
                    .fill(palette.accentHighlight)
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
            playbackRateMenu
            
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
                            .fill(palette.accent.opacity(0.22))
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
            
            repeatModeMenu
        }
        .padding(.vertical, 4)
    }

    private var playbackRateMenu: some View {
        let isActive = playbackRate != 1.0
        return Menu {
            ForEach(availablePlaybackRates, id: \.self) { rate in
                Button {
                    onSelectRate(rate)
                } label: {
                    HStack {
                        Text(playbackRateLabel(for: rate))
                        Spacer(minLength: 8)
                        if playbackRate == rate {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(palette.accent)
                        }
                    }
                }
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(.body)
                    .foregroundStyle(isActive ? palette.accent : .secondary)
                Text(playbackRateText)
                    .font(.system(size: 10))
                    .foregroundStyle(isActive ? palette.accent : .secondary)
            }
        } primaryAction: {
            onCycleRate()
        }
        .sensoryFeedback(.selection, trigger: playbackRate)
        .frame(width: 56)
    }
    
    private var repeatModeMenu: some View {
        let isActive = repeatMode != .off
        return Menu {
            repeatModeMenuRow(mode: .currentSubtitle, icon: "text.quote", titleKey: "playback_repeat_current_sentence")
            repeatModeMenuRow(mode: .wholeTrack, icon: "repeat.circle", titleKey: "playback_repeat_whole_track")
            repeatModeMenuRow(mode: .playlist, icon: "list.bullet.circle", titleKey: "playback_repeat_playlist")
        } label: {
            VStack(spacing: 2) {
                Image(systemName: repeatModeIcon)
                    .font(.body)
                    .foregroundStyle(isActive ? palette.accent : .secondary)
                Text(repeatModeShortLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(isActive ? palette.accent : .secondary)
            }
        } primaryAction: {
            onCycleRepeatMode()
        }
        .sensoryFeedback(.selection, trigger: repeatMode)
        .accessibilityHint(String(localized: LocalizedStringResource("playback_repeat_accessibility_hint", locale: locale)))
        .frame(width: 56)
    }
    
    private func repeatModeMenuRow(mode: PlaybackRepeatMode, icon: String, titleKey: String.LocalizationValue) -> some View {
        Button {
            onSelectRepeatMode(mode)
        } label: {
            HStack {
                Label(String(localized: LocalizedStringResource(titleKey, locale: locale)), systemImage: icon)
                Spacer(minLength: 8)
                if repeatMode == mode {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(palette.accent)
                }
            }
        }
    }
    
    private var repeatModeIcon: String {
        switch repeatMode {
        case .off: return "repeat"
        case .currentSubtitle: return "text.quote"
        case .wholeTrack: return "repeat.circle.fill"
        case .playlist: return "list.bullet.circle.fill"
        }
    }
    
    private var repeatModeShortLabel: String {
        switch repeatMode {
        case .off:
            return String(localized: LocalizedStringResource("playback_repeat_label_off", locale: locale))
        case .currentSubtitle:
            return String(localized: LocalizedStringResource("playback_repeat_label_sentence", locale: locale))
        case .wholeTrack:
            return String(localized: LocalizedStringResource("playback_repeat_label_whole", locale: locale))
        case .playlist:
            return String(localized: LocalizedStringResource("playback_repeat_label_playlist", locale: locale))
        }
    }
    
    private func controlButton(icon: String, label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(isActive ? palette.accent : .secondary)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(isActive ? palette.accent : .secondary)
            }
        }
        .frame(width: 50)
    }

    private func playbackRateLabel(for rate: Float) -> String {
        if rate == 1.0 { return "1x" }
        if rate == floor(rate) { return "\(Int(rate))x" }
        return String(format: "%.2gx", rate)
    }
}

// MARK: - プレビュー

#Preview {
    PlaybackControlsView(
        isPlaying: false,
        currentTime: 35,
        duration: 182,
        playbackRateText: "1x",
        playbackRate: 1.0,
        availablePlaybackRates: [0.5, 0.75, 0.8, 0.9, 1.0, 1.25, 1.5, 2.0],
        repeatMode: .off,
        onTogglePlayPause: {},
        onSkipBackward: {},
        onSkipForward: {},
        onSeek: { _ in },
        onCycleRate: {},
        onSelectRate: { _ in },
        onSelectRepeatMode: { _ in },
        onCycleRepeatMode: {}
    )
    .preferredColorScheme(.dark)
}
