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
        .navigationTitle("処理中")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(viewModel.state.isProcessing)
        .onAppear {
            viewModel.startProcessing(source: audioSource)
        }
        .onChange(of: viewModel.isCompleted) { _, completed in
            if completed, let document = viewModel.document {
                // 処理完了：ProcessingView を PlayerView に置き換える
                // 1. ProcessingView（自分自身）をスタックから削除
                // 2. PlayerView をスタックにプッシュ
                // 結果：PlayerView の「戻る」ボタンで直接 HomeView に戻る
                navigationPath.removeLast()
                navigationPath.append(AppDestination.player(document))
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
                    Text("戻って別のファイルを試してください")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Button {
                        navigationPath.removeLast()
                    } label: {
                        Label("ホームに戻る", systemImage: "house")
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
            StepRow(
                title: "音声の読み込み",
                icon: "waveform",
                state: stepState(for: .loadingAudio)
            )
            StepRow(
                title: "音声認識",
                icon: "mic.fill",
                state: stepState(for: .recognizing)
            )
            StepRow(
                title: "振り仮名生成",
                icon: "character.textbox",
                state: stepState(for: .generatingFurigana)
            )
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }
    
    /// 各ステップの状態を計算する
    private func stepState(for step: ProcessingState) -> StepState {
        let order: [ProcessingState] = [.loadingAudio, .recognizing, .generatingFurigana, .completed]
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
