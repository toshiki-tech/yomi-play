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
    
    /// 相邻字幕之间停顿（秒），便于跟读；0 表示不停顿。单句循环开启时不生效。
    var interSubtitlePauseSeconds: TimeInterval = 0
    
    /// 音声が読み込み完了したか
    var isAudioReady: Bool = false
    
    /// 再生が最後まで到達したときに呼ばれるコールバック（プレイリスト制御用）
    var onPlaybackEnded: (() -> Void)?
    
    // MARK: - 公開プロパティ（VideoPlayer との共有用）
    
    /// VideoPlayer と AVPlayer インスタンスを共有するために公開
    private(set) var player: AVPlayer?
    
    // MARK: - 内部プロパティ
    private var timeObserver: Any?
    private var segments: [TranscriptSegment] = []
    private var statusObserver: NSKeyValueObservation?
    private var durationObserver: NSKeyValueObservation?
    private var endPlaybackObserver: (any NSObjectProtocol)?
    private var interruptionObserver: (any NSObjectProtocol)?
    private var downloadTask: URLSessionDownloadTask?
    /// 句间停顿：上一句字幕 id（用于检测顺序前进）
    private var previousSegmentIdForGap: UUID?
    private var interGapWorkItem: DispatchWorkItem?
    /// 句间停顿等待 UI：此期间锁定为「已进入的下一句」，避免 AVPlayer 略早于 startTime 导致仍落在上句、再次误判 A→B 而横跳
    private var interGapTargetSegmentId: UUID?
    
    // MARK: - 初期化
    
    init() {
        setupAudioSession()
        setupInterruptionObserver()
    }
    
    deinit {
        removeTimeObservers()
        statusObserver?.invalidate()
        durationObserver?.invalidate()
        if let obs = endPlaybackObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        if let obs = interruptionObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        downloadTask?.cancel()
        player?.pause()
    }
    
    // MARK: - 音声セッション設定
    
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
            try session.setActive(true)
            print("AudioPlayerService: セッション設定成功")
        } catch {
            print("AudioPlayerService: セッション設定エラー: \(error)")
        }
    }
    
    /// 来电、短信等系统声音打断时暂停并同步 UI 状态（显示暂停按钮）
    private func setupInterruptionObserver() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            guard let userInfo = notification.userInfo,
                  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
            switch type {
            case .began:
                self.player?.pause()
                self.isPlaying = false
                print("AudioPlayerService: 音声割り込み開始 → 一時停止・UI同期")
            case .ended:
                guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    if self.isAudioReady, self.player != nil {
                        do {
                            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
                        } catch {}
                        self.player?.play()
                        self.player?.rate = self.playbackRate
                        self.isPlaying = true
                        print("AudioPlayerService: 割り込み終了 → 再生再開")
                    }
                }
            @unknown default:
                break
            }
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
                    
                    // 動画の場合は先頭に seek して第一フレームを表示（黒画面を防ぐ）
                    self.player?.seek(to: .zero) { _ in }
                    
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
            self.onPlaybackEnded?()
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
        previousSegmentIdForGap = nil
        interGapWorkItem?.cancel()
        interGapWorkItem = nil
        interGapTargetSegmentId = nil
        loopingSegment = nil
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
        interGapWorkItem?.cancel()
        interGapWorkItem = nil
        interGapTargetSegmentId = nil
        player?.pause()
        isPlaying = false
        print("AudioPlayerService: ⏸️ Paused at \(currentTime)")
    }
    
    /// 指定時間にシークする
    func seek(to time: TimeInterval) {
        interGapWorkItem?.cancel()
        interGapWorkItem = nil
        interGapTargetSegmentId = nil
        // 再生位置を範囲内にクランプしてからシークする
        let clampedTime = max(0, min(duration, time))
        let cmTime = CMTime(seconds: clampedTime, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = clampedTime
        // シーク直後に現在セグメントも更新しておくことで、
        // 進捗バーをドラッグした際に字幕リストも即座に追従する
        updateCurrentSegment()
        previousSegmentIdForGap = currentSegmentID
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
    
    /// 単句ループ対象（nil で解除）。再生位置は呼び出し側で必要なら seek する。
    func setLoopSegment(_ segment: TranscriptSegment?) {
        interGapWorkItem?.cancel()
        interGapWorkItem = nil
        interGapTargetSegmentId = nil
        if segment == nil {
            // 单句循环刚关时，若仍沿用循环期间的 previousId，容易误判为「刚进到下一句」而触发句间停顿 seek，造成两句边界横跳
            previousSegmentIdForGap = currentSegmentID
        }
        loopingSegment = segment
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
            if let forcedId = self.interGapTargetSegmentId {
                self.currentSegmentID = forcedId
            } else {
                self.updateCurrentSegment()
            }
            if self.interSubtitlePauseSeconds > 0, self.loopingSegment == nil {
                self.handleInterSubtitleGapIfNeeded()
            } else {
                self.previousSegmentIdForGap = self.currentSegmentID
            }
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
            interGapWorkItem?.cancel()
            interGapWorkItem = nil
            seek(to: segment.startTime)
        }
    }
    
    /// 順播放到「下一句」时插入停顿（仅按字幕列表顺序前进时触发）
    private func handleInterSubtitleGapIfNeeded() {
        guard interGapWorkItem == nil else { return }
        let newId = currentSegmentID
        guard let prevId = previousSegmentIdForGap, let nid = newId, prevId != nid else {
            previousSegmentIdForGap = newId
            return
        }
        guard let oi = segments.firstIndex(where: { $0.id == prevId }),
              let ni = segments.firstIndex(where: { $0.id == nid }),
              ni == oi + 1 else {
            previousSegmentIdForGap = newId
            return
        }
        let pauseSeconds = max(0, interSubtitlePauseSeconds)
        guard pauseSeconds > 0 else {
            previousSegmentIdForGap = newId
            return
        }
        let nextSeg = segments[ni]
        pause()
        // 对齐到句首常落在关键帧略前，contains 仍判在上句 → 又触发一次「顺播进下句」，形成两句间横跳
        let span = max(0, nextSeg.endTime - nextSeg.startTime)
        let inset = min(0.05, max(0.001, span > 0 ? span * 0.02 : 0.001))
        var seekTime = nextSeg.startTime + inset
        if seekTime >= nextSeg.endTime {
            seekTime = max(nextSeg.startTime, nextSeg.endTime - 0.0005)
        }
        seek(to: seekTime)
        interGapTargetSegmentId = nextSeg.id
        currentSegmentID = nextSeg.id
        previousSegmentIdForGap = nextSeg.id
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.interGapWorkItem = nil
            self.interGapTargetSegmentId = nil
            self.play()
        }
        interGapWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + pauseSeconds, execute: work)
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
