//
//  SettingsView.swift
//  YomiPlay
//
//  アプリ設定画面
//

import SwiftUI

struct SettingsView: View {
    @State private var showFurigana: Bool = UserDefaults.standard.bool(forKey: "showFurigana")
    @State private var showRomaji: Bool = UserDefaults.standard.bool(forKey: "showRomaji")
    @State private var showEnglish: Bool = UserDefaults.standard.bool(forKey: "showEnglish")
    @State private var fontSize: CGFloat = CGFloat(UserDefaults.standard.double(forKey: "fontSize"))
    @State private var targetLanguageCode: String = UserDefaults.standard.string(forKey: "targetLanguageCode") ?? "zh-Hans"
    @AppStorage("whisperModelVariant") private var recognitionModeRaw: String = "small"
    @AppStorage("appInterfaceLanguage") private var appInterfaceLanguage: String = "system"

    // 初期値が0（未設定）の場合はデフォルト値を設定
    init() {
        WhisperSpeechRecognitionService.ensureModelVariantInitialized()
        if UserDefaults.standard.object(forKey: "showFurigana") == nil { _showFurigana = State(initialValue: true) }
        if UserDefaults.standard.object(forKey: "showRomaji") == nil { _showRomaji = State(initialValue: true) }
        if UserDefaults.standard.object(forKey: "showEnglish") == nil { _showEnglish = State(initialValue: true) }
        if UserDefaults.standard.double(forKey: "fontSize") == 0 { _fontSize = State(initialValue: 18) }
    }
    
    /// 翻译目标语言列表（针对日文字幕的翻译，不包含日文本身）
    let languages = [
        ("zh-Hans", "简体中文"),
        ("zh-Hant", "繁體中文"),
        ("en", "English")
    ]
    
    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Text("YomiPlay Premium")
                        .font(.headline)
                        .foregroundStyle(.linearGradient(colors: [.green, .blue], startPoint: .leading, endPoint: .trailing))
                    Text("Unlock all features and support development.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            
            Section {
                settingsToggle(icon: "character.textbox", title: "furigana", color: .green, isOn: $showFurigana) {
                    UserDefaults.standard.set(showFurigana, forKey: "showFurigana")
                    HapticManager.shared.selection()
                }
                
                settingsToggle(icon: "a.circle", title: "romaji", color: .blue, isOn: $showRomaji) {
                    UserDefaults.standard.set(showRomaji, forKey: "showRomaji")
                    HapticManager.shared.selection()
                }
                
                settingsToggle(icon: "book.closed", title: "loanword_english", color: .orange, isOn: $showEnglish) {
                    UserDefaults.standard.set(showEnglish, forKey: "showEnglish")
                    HapticManager.shared.selection()
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Label {
                        Text("font_size").font(.subheadline)
                    } icon: {
                        Image(systemName: "textformat.size").foregroundStyle(.purple)
                    }
                    
                    HStack {
                        Image(systemName: "textformat.size.smaller").font(.caption).foregroundStyle(.secondary)
                        Slider(value: $fontSize, in: 12...48, step: 1)
                            .onChange(of: fontSize) { _, newValue in
                                UserDefaults.standard.set(Double(newValue), forKey: "fontSize")
                                HapticManager.shared.impact(style: .soft)
                            }
                            .tint(.purple)
                        Image(systemName: "textformat.size.larger").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("display_settings")
            }

            Section {
                Picker(selection: $appInterfaceLanguage) {
                    Text("interface_language_system").tag("system")
                    Text("interface_language_en").tag("en")
                    Text("interface_language_ja").tag("ja")
                    Text("interface_language_zh_hans").tag("zh-Hans")
                    Text("interface_language_zh_hant").tag("zh-Hant")
                } label: {
                    Label {
                        Text("interface_language_label").font(.subheadline)
                    } icon: {
                        Image(systemName: "globe").foregroundStyle(.green)
                    }
                }
                .onChange(of: appInterfaceLanguage) { _, _ in
                    HapticManager.shared.selection()
                }
            } header: {
                Text("interface_language_section")
            } footer: {
                Text("interface_language_footer")
            }
            
            Section {
                Picker(selection: $targetLanguageCode) {
                    ForEach(languages, id: \.0) { lang in
                        Text(lang.1).tag(lang.0)
                    }
                } label: {
                    Label {
                        Text("target_language").font(.subheadline)
                    } icon: {
                        Image(systemName: "globe").foregroundStyle(.blue)
                    }
                }
                .onChange(of: targetLanguageCode) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: "targetLanguageCode")
                    HapticManager.shared.success()
                }
            } header: {
                Text("translation_settings")
            }
            
            Section {
                Picker(selection: $recognitionModeRaw) {
                    ForEach(WhisperSpeechRecognitionService.RecognitionMode.allCases, id: \.rawValue) { mode in
                        Text(recognitionModeTitleKey(mode)).tag(mode.rawValue)
                    }
                } label: {
                    Label {
                        Text("recognition_mode_label").font(.subheadline)
                    } icon: {
                        Image(systemName: "cpu").foregroundStyle(.green)
                    }
                }
                .onChange(of: recognitionModeRaw) { _, _ in
                    HapticManager.shared.selection()
                }
            } header: {
                Text("recognition_mode_section")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(recognitionModeHintKey)
                    Text("recognition_mode_device_recommendation \(recommendedModeDisplayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                infoRow(title: "version", value: "1.0.0", icon: "info.circle", color: .secondary)
                infoRow(title: "engine", value: "Whisper (On-Device)", icon: "cpu", color: .secondary)
            } header: {
                Text("about")
            }
        }
        .navigationTitle("settings")
    }

    private func recognitionModeTitleKey(_ mode: WhisperSpeechRecognitionService.RecognitionMode) -> LocalizedStringKey {
        switch mode {
        case .tiny: return "recognition_mode_tiny"
        case .base: return "recognition_mode_base"
        case .small: return "recognition_mode_small"
        case .medium: return "recognition_mode_medium"
        case .large: return "recognition_mode_large"
        }
    }

    private var recognitionModeHintKey: LocalizedStringKey {
        let mode = WhisperSpeechRecognitionService.RecognitionMode(rawValue: recognitionModeRaw) ?? .small
        switch mode {
        case .tiny: return "recognition_mode_tiny_hint"
        case .base: return "recognition_mode_base_hint"
        case .small: return "recognition_mode_small_hint"
        case .medium: return "recognition_mode_medium_hint"
        case .large: return "recognition_mode_large_hint"
        }
    }

    private var recommendedModeDisplayName: String {
        let mode = WhisperSpeechRecognitionService.recommendedModeForDevice
        switch mode {
        case .tiny: return String(localized: "recognition_mode_tiny")
        case .base: return String(localized: "recognition_mode_base")
        case .small: return String(localized: "recognition_mode_small")
        case .medium: return String(localized: "recognition_mode_medium")
        case .large: return String(localized: "recognition_mode_large")
        }
    }

    private func settingsToggle(icon: String, title: LocalizedStringKey, color: Color, isOn: Binding<Bool>, action: @escaping () -> Void) -> some View {
        Toggle(isOn: isOn) {
            Label {
                Text(title).font(.subheadline)
            } icon: {
                Image(systemName: icon).foregroundStyle(color)
            }
        }
        .onChange(of: isOn.wrappedValue) { _, _ in action() }
        .tint(color)
    }
    
    private func infoRow(title: LocalizedStringKey, value: String, icon: String, color: Color) -> some View {
        HStack {
            Label {
                Text(title).font(.subheadline)
            } icon: {
                Image(systemName: icon).foregroundStyle(color)
            }
            Spacer()
            Text(value).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

#Preview {
    SettingsView()
}
