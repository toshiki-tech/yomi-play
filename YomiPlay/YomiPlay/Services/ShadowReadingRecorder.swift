//
//  ShadowReadingRecorder.swift
//  YomiPlay
//
//  跟读短时录音（m4a），供本地 Whisper 转写
//

import AVFoundation
import Foundation

final class ShadowReadingRecorder: NSObject, AVAudioRecorderDelegate {

    private var recorder: AVAudioRecorder?
    private var activeURL: URL?

    /// 请求麦克风权限
    func requestPermission() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
    }

    /// 准备录音文件 URL（临时目录）
    func makeRecordingURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
        let name = "shadow_reading_\(UUID().uuidString).m4a"
        return dir.appendingPathComponent(name)
    }

    func startRecording(to url: URL) throws {
        stopRecording()

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        let r = try AVAudioRecorder(url: url, settings: settings)
        r.delegate = self
        guard r.prepareToRecord(), r.record() else {
            throw NSError(domain: "ShadowReadingRecorder", code: -2, userInfo: [NSLocalizedDescriptionKey: "record_start_failed"])
        }
        recorder = r
        activeURL = url
    }

    /// 停止并返回录音文件 URL（若未在录则 nil）
    func stopRecording() -> URL? {
        recorder?.stop()
        recorder = nil
        let url = activeURL
        activeURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return url
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        print("ShadowReadingRecorder: encode error \(String(describing: error))")
    }
}
