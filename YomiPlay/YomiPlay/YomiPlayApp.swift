//
//  YomiPlayApp.swift
//  YomiPlay
//
//  アプリのエントリーポイント
//

import SwiftUI
import AVFoundation

@main
struct YomiPlayApp: App {
    
    init() {
        configureAudioSession()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
    
    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
        } catch {
            print("AudioSession初期設定エラー: \(error)")
        }
    }
}
