//
//  PlayerViewModel.swift
//  YomiPlay
//
//  プレーヤー画面のViewModel
//  再生制御・字幕同期・設定・字幕編集を管理する
//

import Foundation
import AVFoundation

// MARK: - プレーヤー画面ViewModel

@Observable
final class PlayerViewModel {
    
    // MARK: - 公開プロパティ
    
    var document: TranscriptDocument
    var playerService: AudioPlayerService
    
    // 表示設定
    var showFurigana: Bool = true
    var showRomaji: Bool = true
    var fontSize: CGFloat = 18
    var isLooping: Bool = false
    
    // 再生速度
    var playbackRate: Float = 1.0
    static let availableRates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
    
    // 字幕編集
    var editingSegmentID: UUID? = nil
    var editingText: String = ""
    
    private let furiganaService = CFStringTokenizerFuriganaService()
    
    // MARK: - 初期化
    
    init(document: TranscriptDocument) {
        self.document = document
        self.playerService = AudioPlayerService()
        
        if let url = document.source.playbackURL {
            playerService.loadAudio(from: url)
        }
        playerService.setSegments(document.segments)
    }
    
    // MARK: - 再生コントロール
    
    func togglePlayPause() {
        playerService.togglePlayPause()
    }
    
    func skipBackward() {
        playerService.skip(seconds: -5)
    }
    
    func skipForward() {
        playerService.skip(seconds: 10)
    }
    
    func seek(to time: TimeInterval) {
        playerService.seek(to: time)
    }
    
    // MARK: - 再生速度
    
    func cyclePlaybackRate() {
        guard let currentIndex = Self.availableRates.firstIndex(of: playbackRate) else {
            playbackRate = 1.0
            playerService.setPlaybackRate(1.0)
            return
        }
        let nextIndex = (currentIndex + 1) % Self.availableRates.count
        playbackRate = Self.availableRates[nextIndex]
        playerService.setPlaybackRate(playbackRate)
    }
    
    var playbackRateText: String {
        if playbackRate == 1.0 { return "1x" }
        if playbackRate == floor(playbackRate) { return "\(Int(playbackRate))x" }
        return String(format: "%.2gx", playbackRate)
    }
    
    // MARK: - 字幕操作
    
    func onSegmentTapped(_ segment: TranscriptSegment) {
        playerService.seek(to: segment.startTime)
        if !playerService.isPlaying {
            playerService.play()
        }
    }
    
    func toggleCurrentLoop() {
        if isLooping {
            isLooping = false
            playerService.setLoopSegment(nil)
        } else if let segmentID = playerService.currentSegmentID,
                  let segment = document.segments.first(where: { $0.id == segmentID }) {
            isLooping = true
            playerService.setLoopSegment(segment)
        }
    }
    
    // MARK: - 字幕編集
    
    /// 編集を開始する
    func startEditing(segment: TranscriptSegment) {
        editingSegmentID = segment.id
        editingText = segment.originalText
    }
    
    /// 編集をキャンセルする
    func cancelEditing() {
        editingSegmentID = nil
        editingText = ""
    }
    
    /// 編集を確定し、振り仮名を再生成する
    func confirmEditing() {
        guard let segmentID = editingSegmentID,
              let index = document.segments.firstIndex(where: { $0.id == segmentID }) else {
            cancelEditing()
            return
        }
        
        let newText = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newText.isEmpty else {
            cancelEditing()
            return
        }
        
        // 振り仮名を再生成（バックグラウンド）
        let segmentIndex = index
        Task {
            let tokens = await furiganaService.generateFurigana(for: newText)
            
            await MainActor.run {
                document.segments[segmentIndex].originalText = newText
                document.segments[segmentIndex].tokens = tokens
                
                // セグメント情報を再設定
                playerService.setSegments(document.segments)
                
                // 保存
                saveDocument()
                
                editingSegmentID = nil
                editingText = ""
            }
        }
    }
    
    /// ドキュメントを保存する
    func saveDocument() {
        do {
            try DocumentStore.shared.save(document)
            print("PlayerViewModel: ドキュメント保存完了")
        } catch {
            print("PlayerViewModel: 保存失敗: \(error)")
        }
    }
    
    /// 現在の再生位置をドキュメントに保存する（画面を出るときに呼ぶ）
    func savePlaybackPosition() {
        document.lastPlaybackPosition = playerService.currentTime
        saveDocument()
    }
    
    // MARK: - 設定
    
    func adjustFontSize(by delta: CGFloat) {
        fontSize = max(12, min(32, fontSize + delta))
    }
    
    // MARK: - ヘルパー
    
    var isPlaying: Bool { playerService.isPlaying }
    
    var progress: Double {
        guard playerService.duration > 0 else { return 0 }
        return playerService.currentTime / playerService.duration
    }
}
