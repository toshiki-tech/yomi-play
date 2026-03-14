//
//  ProcessingView.swift
//  YomiPlay
//
//  処理中画面
//  音声認識→振り仮名生成の処理進捗を表示する
//

import SwiftUI

// MARK: - 処理中画面

/// 音声認識と振り仮名生成の処理進捗を表示する
struct ProcessingView: View {
    let audioSource: AudioSource
    @Binding var navigationPath: NavigationPath
    @State private var viewModel = ProcessingViewModel()
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            // アニメーション付きアイコン
            processingIcon
            
            // ステータスメッセージ
            statusSection
            
            Spacer()
        }
        .padding(24)
        .navigationTitle("processing")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(viewModel.state.isProcessing)
        .onAppear {
            // 防止 SwiftUI 重复触发 onAppear 时重复开始处理，导致生成多条记录
            if viewModel.state == .idle {
                viewModel.startProcessing(source: audioSource)
            }
        }
        .onChange(of: viewModel.isCompleted) { _, completed in
            if completed, let document = viewModel.document {
                if !navigationPath.isEmpty {
                    navigationPath.removeLast()
                    navigationPath.append(AppDestination.player(documents: [document], currentIndex: 0))
                }
            }
        }
    }
    
    // MARK: - 処理用アイコン
    
    private var processingIcon: some View {
        ZStack {
            // 背景の円
            Circle()
                .fill(Color.accentColor.opacity(0.1))
                .frame(width: 140, height: 140)
            
            // 状態に応じたアイコン
            Group {
                switch viewModel.state {
                case .completed:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                    
                case .error:
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.red)
                        .transition(.scale.combined(with: .opacity))
                    
                default:
                    ProgressView()
                        .controlSize(.large)
                        .tint(.accentColor)
                }
            }
            .animation(.spring(duration: 0.5), value: viewModel.state)
        }
    }
    
    // MARK: - ステータスセクション
    
    private var statusSection: some View {
        VStack(spacing: 16) {
            Text(viewModel.state.displayText)
                .font(.title3)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .animation(.easeInOut, value: viewModel.state)
            
            // 処理ステップのインジケーター
            if viewModel.state.isProcessing || viewModel.state == .completed {
                stepsIndicator
            }
            
            // エラー時の説明とボタン
            if case .error = viewModel.state {
                VStack(spacing: 12) {
                    Text("please_go_back_and_try_another_file")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Button {
                        if !navigationPath.isEmpty {
                            navigationPath.removeLast()
                        }
                    } label: {
                        Label("back_to_home", systemImage: "house")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.accentColor)
                            )
                    }
                }
            }
        }
    }
    
    // MARK: - ステップインジケーター
    
    private var stepsIndicator: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.hasSRT {
                StepRow(
                    title: String(localized: "parsing_subtitles_2"),
                    icon: "doc.text",
                    state: srtStepState(for: .parsingSRT)
                )
                StepRow(
                    title: String(localized: "generating_phonetic_subtitles"),
                    icon: "character.textbox",
                    state: srtStepState(for: .generatingFurigana)
                )
            } else {
                // 通常フロー：リモートは 解析→下载→加载→识别→生成注音；ローカルは 加载→识别→生成注音
                if audioSource.type == .remote {
                    StepRow(
                        title: String(localized: "resolving_podcast_link"),
                        icon: "link",
                        state: stepState(for: .resolvingRemoteSource)
                    )
                    StepRow(
                        title: String(localized: "downloading_podcast_audio"),
                        icon: "arrow.down.circle",
                        state: stepState(for: .downloadingPodcast)
                    )
                }
                StepRow(
                    title: String(localized: "loading_audio"),
                    icon: "waveform",
                    state: stepState(for: .loadingAudio)
                )
                StepRow(
                    title: String(localized: "speech_recognition"),
                    icon: "mic.fill",
                    state: stepState(for: .recognizing)
                )
                StepRow(
                    title: String(localized: "generating_phonetic_subtitles"),
                    icon: "character.textbox",
                    state: stepState(for: .generatingFurigana)
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }
    
    /// 通常フロー：リモートは 解析→下载→加载→识别→生成、ローカルは 加载→识别→生成 の順で状態を計算
    private func stepState(for step: ProcessingState) -> StepState {
        let order: [ProcessingState] = audioSource.type == .remote
            ? [.resolvingRemoteSource, .downloadingPodcast, .loadingAudio, .recognizing, .generatingFurigana, .completed]
            : [.loadingAudio, .recognizing, .generatingFurigana, .completed]
        let currentIndex = order.firstIndex(of: viewModel.state) ?? 0
        let stepIndex = order.firstIndex(of: step) ?? 0
        if currentIndex > stepIndex { return .completed }
        if currentIndex == stepIndex { return .active }
        return .pending
    }
    
    /// SRT フロー：各ステップの状態を計算する
    private func srtStepState(for step: ProcessingState) -> StepState {
        let order: [ProcessingState] = [.parsingSRT, .generatingFurigana, .completed]
        let currentIndex = order.firstIndex(of: viewModel.state) ?? 0
        let stepIndex = order.firstIndex(of: step) ?? 0
        
        if currentIndex > stepIndex {
            return .completed
        } else if currentIndex == stepIndex {
            return .active
        } else {
            return .pending
        }
    }
}

// MARK: - ステップ状態

enum StepState {
    case pending
    case active
    case completed
}

// MARK: - ステップ行ビュー

/// 処理ステップの一行表示
struct StepRow: View {
    let title: String
    let icon: String
    let state: StepState
    
    var body: some View {
        HStack(spacing: 12) {
            // ステータスアイコン
            ZStack {
                Circle()
                    .fill(circleColor.opacity(0.2))
                    .frame(width: 32, height: 32)
                
                Group {
                    switch state {
                    case .completed:
                        Image(systemName: "checkmark")
                            .foregroundStyle(.green)
                            .fontWeight(.bold)
                    case .active:
                        ProgressView()
                            .controlSize(.small)
                    case .pending:
                        Image(systemName: icon)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
            }
            
            Text(title)
                .font(.subheadline)
                .foregroundStyle(state == .pending ? .secondary : .primary)
                .fontWeight(state == .active ? .semibold : .regular)
            
            Spacer()
        }
    }
    
    private var circleColor: Color {
        switch state {
        case .completed: return .green
        case .active: return .accentColor
        case .pending: return .gray
        }
    }
}

// MARK: - プレビュー

#Preview {
    @Previewable @State var path = NavigationPath()
    NavigationStack(path: $path) {
        ProcessingView(
            audioSource: AudioSource(
                type: .local,
                title: "サンプル音声"
            ),
            navigationPath: $path
        )
    }
}
