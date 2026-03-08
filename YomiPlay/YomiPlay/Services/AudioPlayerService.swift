//
//  AudioPlayerService.swift
//  YomiPlay
//
//  音声再生サービス
//  AVPlayerを使用した音声再生の管理
//

import Foundation
import AVFoundation
import Combine

// MARK: - 音声再生サービス

/// AVPlayerをラップした音声再生サービス
@Observable
final class AudioPlayerService {
    
    // MARK: - 公開プロパティ
    
    /// 再生中かどうか
    var isPlaying: Bool = false
    
    /// 現在の再生時間（秒）
    var currentTime: TimeInterval = 0
    
    /// 音声の総再生時間（秒）
    var duration: TimeInterval = 0
    
    /// 再生速度
    var playbackRate: Float = 1.0
    
    /// 現在再生中のセグメントID
    var currentSegmentID: UUID?
    
    /// ループ再生中のセグメント
    var loopingSegment: TranscriptSegment?
    
    /// 音声が読み込み完了したか
    var isAudioReady: Bool = false
    
    // MARK: - 内部プロパティ
    
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var segments: [TranscriptSegment] = []
    private var statusObserver: NSKeyValueObservation?
    private var durationObserver: NSKeyValueObservation?
    private var endPlaybackObserver: (any NSObjectProtocol)?
    private var downloadTask: URLSessionDownloadTask?
    
    // MARK: - 初期化
    
    init() {
        setupAudioSession()
    }
    
    deinit {
        removeTimeObservers()
        statusObserver?.invalidate()
        durationObserver?.invalidate()
        if let obs = endPlaybackObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        downloadTask?.cancel()
        player?.pause()
    }
    
    // MARK: - 音声セッション設定
    
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
            print("AudioPlayerService: セッション設定成功")
        } catch {
            print("AudioPlayerService: セッション設定エラー: \(error)")
        }
    }
    
    // MARK: - 音声の読み込み
    
    /// URLから音声を読み込む（リモートURLの場合は先にダウンロードする）
    func loadAudio(from url: URL) {
        print("AudioPlayerService: Loading audio from \(url)")
        
        // 状態をリセット
        cleanup()
        
        if url.isFileURL {
            // ローカルファイルの場合はそのまま再生
            print("AudioPlayerService: ローカルファイルを読み込み")
            setupPlayer(with: url)
        } else {
            // リモートURLの場合はダウンロードしてから再生
            print("AudioPlayerService: リモートファイルをダウンロード開始")
            downloadAndPlay(from: url)
        }
    }
    
    /// リモートURLからダウンロードして再生する
    private func downloadAndPlay(from url: URL) {
        downloadTask?.cancel()
        
        let task = URLSession.shared.downloadTask(with: url) { [weak self] tempURL, response, error in
            guard let self = self else { return }
            
            if let error = error {
                print("AudioPlayerService: ダウンロードエラー: \(error)")
                return
            }
            
            guard let tempURL = tempURL else {
                print("AudioPlayerService: ダウンロード一時URLがnil")
                return
            }
            
            // レスポンスを確認
            if let httpResponse = response as? HTTPURLResponse {
                print("AudioPlayerService: HTTP ステータス: \(httpResponse.statusCode)")
                print("AudioPlayerService: Content-Type: \(httpResponse.mimeType ?? "不明")")
            }
            
            // ドキュメントディレクトリに保存
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fileName = url.lastPathComponent.isEmpty ? "downloaded_audio.mp3" : url.lastPathComponent
            let localURL = documentsURL.appendingPathComponent("yomiplay_\(fileName)")
            
            do {
                // 既存ファイルがあれば削除
                if FileManager.default.fileExists(atPath: localURL.path) {
                    try FileManager.default.removeItem(at: localURL)
                }
                try FileManager.default.moveItem(at: tempURL, to: localURL)
                print("AudioPlayerService: ダウンロード完了: \(localURL)")
                
                // メインスレッドでプレーヤーを設定
                DispatchQueue.main.async {
                    self.setupPlayer(with: localURL)
                }
            } catch {
                print("AudioPlayerService: ファイル保存エラー: \(error)")
            }
        }
        
        downloadTask = task
        task.resume()
    }
    
    /// AVPlayerを設定する
    private func setupPlayer(with url: URL) {
        print("AudioPlayerService: プレーヤーを設定中: \(url)")
        
        let playerItem = AVPlayerItem(url: url)
        
        // ステータス監視を追加
        statusObserver = playerItem.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch item.status {
                case .readyToPlay:
                    print("AudioPlayerService: ✅ PlayerItem is ready to play")
                    self.isAudioReady = true
                    
                    // durationを取得
                    let seconds = CMTimeGetSeconds(item.duration)
                    if seconds.isFinite && seconds > 0 {
                        self.duration = seconds
                        print("AudioPlayerService: 音声の長さ: \(seconds)秒")
                    }
                case .failed:
                    print("AudioPlayerService: ❌ PlayerItem failed: \(String(describing: item.error))")
                case .unknown:
                    print("AudioPlayerService: ⏳ PlayerItem status unknown (loading...)")
                @unknown default:
                    break
                }
            }
        }
        
        let player = AVPlayer(playerItem: playerItem)
        player.automaticallyWaitsToMinimizeStalling = true
        self.player = player
        
        // 再生終了時に isPlaying をリセット
        if let obs = endPlaybackObserver {
            NotificationCenter.default.removeObserver(obs)
            endPlaybackObserver = nil
        }
        endPlaybackObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.isPlaying = false
            self.seek(to: 0)
        }
        
        // 非同期でdurationも取得を試みる（バックアップ）
        Task {
            if let loadedDuration = try? await playerItem.asset.load(.duration) {
                let seconds = CMTimeGetSeconds(loadedDuration)
                if seconds.isFinite && seconds > 0 {
                    await MainActor.run {
                        if self.duration == 0 {
                            self.duration = seconds
                            print("AudioPlayerService: (async) 音声の長さ: \(seconds)秒")
                        }
                    }
                }
            }
        }
        
        setupTimeObserver()
    }
    
    /// 状態をリセットする
    private func cleanup() {
        removeTimeObservers()
        statusObserver?.invalidate()
        durationObserver?.invalidate()
        if let obs = endPlaybackObserver {
            NotificationCenter.default.removeObserver(obs)
            endPlaybackObserver = nil
        }
        downloadTask?.cancel()
        player?.pause()
        
        isPlaying = false
        isAudioReady = false
        currentTime = 0
        duration = 0
        currentSegmentID = nil
    }
    
    /// 字幕セグメントを設定する（同期表示用）
    func setSegments(_ segments: [TranscriptSegment]) {
        self.segments = segments
    }
    
    // MARK: - 再生コントロール
    
    /// 再生・一時停止を切り替える
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    /// 再生する
    func play() {
        guard let player = player else {
            print("AudioPlayerService: プレーヤーがnil")
            return
        }
        guard isAudioReady else {
            print("AudioPlayerService: 音声未準備のため再生しません")
            return
        }
        
        // 再生直前にセッションをアクティブ化
        do {
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("AudioPlayerService: Session活性化失敗: \(error)")
        }
        
        player.play()
        player.rate = playbackRate
        isPlaying = true
        print("AudioPlayerService: ▶️ Playing at rate \(playbackRate), currentTime=\(currentTime), duration=\(duration)")
    }
    
    /// 一時停止する
    func pause() {
        player?.pause()
        isPlaying = false
        print("AudioPlayerService: ⏸️ Paused at \(currentTime)")
    }
    
    /// 指定時間にシークする
    func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
    }
    
    /// 指定秒数をスキップする（正の値で前進、負の値で後退）
    func skip(seconds: TimeInterval) {
        let newTime = max(0, min(duration, currentTime + seconds))
        seek(to: newTime)
    }
    
    /// 再生速度を設定する
    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        if isPlaying {
            player?.rate = rate
        }
    }
    
    /// セグメントのループ再生を設定する
    func setLoopSegment(_ segment: TranscriptSegment?) {
        loopingSegment = segment
        if let segment = segment {
            seek(to: segment.startTime)
            play()
        }
    }
    
    // MARK: - 時間監視
    
    /// 定期的に再生時間を更新するオブザーバーを設定
    private func setupTimeObserver() {
        guard let player = player else { return }
        
        // 0.1秒ごとに更新
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            guard let self = self else { return }
            let seconds = CMTimeGetSeconds(time)
            guard seconds.isFinite else { return }
            
            self.currentTime = seconds
            self.updateCurrentSegment()
            self.handleLoopPlayback()
        }
    }
    
    /// 時間監視オブザーバーを削除
    private func removeTimeObservers() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
    }
    
    /// 現在の再生位置に対応するセグメントを更新
    private func updateCurrentSegment() {
        let current = currentTime
        if let segment = segments.first(where: { $0.contains(time: current) }) {
            if currentSegmentID != segment.id {
                currentSegmentID = segment.id
            }
        }
    }
    
    /// ループ再生の処理
    private func handleLoopPlayback() {
        guard let segment = loopingSegment else { return }
        
        if currentTime >= segment.endTime {
            seek(to: segment.startTime)
        }
    }
    
    // MARK: - フォーマット

    /// 時間をmm:ss形式にフォーマットする
    static func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite && !time.isNaN else { return "0:00" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
