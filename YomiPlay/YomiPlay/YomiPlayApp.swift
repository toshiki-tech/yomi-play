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
    @AppStorage("appInterfaceLanguage") private var appInterfaceLanguage: String = "system"
    @AppStorage("appInterfaceTheme") private var appInterfaceTheme: String = "system"

    init() {
        WhisperSpeechRecognitionService.ensureModelVariantInitialized()
        configureAudioSession()
    }

    private var effectiveLocale: Locale {
        if appInterfaceLanguage.isEmpty || appInterfaceLanguage == "system" {
            return Locale.current
        }
        return Locale(identifier: appInterfaceLanguage)
    }

    private var effectiveColorScheme: ColorScheme? {
        switch appInterfaceTheme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.locale, effectiveLocale)
                .preferredColorScheme(effectiveColorScheme)
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
