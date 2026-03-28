//
//  SettingsView.swift
//  YomiPlay
//
//  アプリ設定画面：Free/Pro 动态头部 + iOS 18 风格
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL
    @State private var showFurigana: Bool = UserDefaults.standard.bool(forKey: "showFurigana")
    @State private var showRomaji: Bool = UserDefaults.standard.bool(forKey: "showRomaji")
    @State private var showEnglish: Bool = UserDefaults.standard.bool(forKey: "showEnglish")
    @State private var fontSize: CGFloat = CGFloat(UserDefaults.standard.double(forKey: "fontSize"))
    @State private var targetLanguageCode: String
    @AppStorage("whisperModelVariant") private var recognitionModeRaw: String = "small"
    @AppStorage(WhisperSpeechRecognitionService.sourceLanguageDefaultsKey) private var recognitionSourceLanguage: String = "ja"
    @AppStorage("appInterfaceLanguage") private var appInterfaceLanguage: String = "system"
    @AppStorage("appInterfaceTheme") private var appInterfaceTheme: String = "system"
    @AppStorage("translationEnabled") private var translationEnabled: Bool = false
    @State private var showTranslationNetworkHint: Bool = false
    @State private var showModelDownloadConfirmAlert: Bool = false
    @State private var pendingDownloadMode: WhisperSpeechRecognitionService.RecognitionMode?
    @State private var previousRecognitionModeRaw: String = "small"
    @State private var showPaywall: Bool = false
    @State private var showHelpSheet: Bool = false
    @State private var showClearCacheConfirm: Bool = false
    @State private var clearCacheResultMessage: String?
    @State private var showClearCacheResult: Bool = false
    private var subscription: SubscriptionManager { SubscriptionManager.shared }

    init() {
        WhisperSpeechRecognitionService.ensureModelVariantInitialized()
        if UserDefaults.standard.object(forKey: "showFurigana") == nil { _showFurigana = State(initialValue: true) }
        if UserDefaults.standard.object(forKey: "showRomaji") == nil { _showRomaji = State(initialValue: true) }
        if UserDefaults.standard.object(forKey: "showEnglish") == nil { _showEnglish = State(initialValue: true) }
        if UserDefaults.standard.double(forKey: "fontSize") == 0 { _fontSize = State(initialValue: 18) }
        let raw = UserDefaults.standard.string(forKey: WhisperSpeechRecognitionService.modelVariantDefaultsKey) ?? WhisperSpeechRecognitionService.recommendedModeForDevice.rawValue
        _previousRecognitionModeRaw = State(initialValue: raw)

        let initialTarget: String
        if let s = UserDefaults.standard.string(forKey: "targetLanguageCode"), !s.isEmpty {
            initialTarget = TranslationTargetLanguageOptions.normalizedCode(s)
        } else {
            initialTarget = TranslationTargetLanguageOptions.defaultTargetCode()
            UserDefaults.standard.set(initialTarget, forKey: "targetLanguageCode")
        }
        _targetLanguageCode = State(initialValue: initialTarget)
    }
    
    var body: some View {
        List {
            Section {
                SettingsHeaderView(
                    subscription: subscription,
                    onUpgradeTap: {
                        showPaywall = true
                    }
                )
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            
            Section {
                Picker(selection: $appInterfaceTheme) {
                    Text("interface_theme_system").tag("system")
                    Text("interface_theme_light").tag("light")
                    Text("interface_theme_dark").tag("dark")
                } label: {
                    Label {
                        Text("interface_theme_label").font(.subheadline)
                    } icon: {
                        Image(systemName: "paintbrush").foregroundStyle(.green)
                    }
                }
                .onChange(of: appInterfaceTheme) { _, _ in
                    HapticManager.shared.selection()
                }
                
                Picker(selection: $appInterfaceLanguage) {
                    Text(String(localized: LocalizedStringResource("interface_language_system", locale: locale))).tag("system")
                    Text(String(localized: LocalizedStringResource("interface_language_en", locale: locale))).tag("en")
                    Text(String(localized: LocalizedStringResource("interface_language_ja", locale: locale))).tag("ja")
                    Text(String(localized: LocalizedStringResource("interface_language_zh_hans", locale: locale))).tag("zh-Hans")
                    Text(String(localized: LocalizedStringResource("interface_language_zh_hant", locale: locale))).tag("zh-Hant")
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
                Text("interface_settings_section")
            } footer: {
                Text("interface_language_footer")
            }
            
            Section {
                // 先选「语言」
                Picker(selection: $recognitionSourceLanguage) {
                    Text("recognition_language_auto").tag("auto")
                    Text("recognition_language_ja").tag("ja")
                    Text("recognition_language_en").tag("en")
                    Text("recognition_language_zh").tag("zh")
                } label: {
                    Label {
                        Text("recognition_language_label").font(.subheadline)
                    } icon: {
                        Image(systemName: "globe").foregroundStyle(.blue)
                    }
                }
                .onChange(of: recognitionSourceLanguage) { _, _ in
                    HapticManager.shared.selection()
                }

                // 再选「模型」
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
                .onChange(of: recognitionModeRaw) { _, newValue in
                    guard let mode = WhisperSpeechRecognitionService.RecognitionMode(rawValue: newValue) else {
                        HapticManager.shared.selection()
                        return
                    }
                    // 高精度 / 超大：若未同梱则先弹窗确认再切换；同梱则直接切换
                    if mode == .medium || mode == .large {
                        if !WhisperSpeechRecognitionService.isModelAvailableLocally(mode) {
                            recognitionModeRaw = previousRecognitionModeRaw
                            pendingDownloadMode = mode
                            showModelDownloadConfirmAlert = true
                            return
                        }
                    }
                    previousRecognitionModeRaw = newValue
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
            .alert(String(localized: "recognition_model_download_confirm_title"), isPresented: $showModelDownloadConfirmAlert) {
                Button(String(localized: "recognition_model_download_confirm_button"), role: .none) {
                    if let mode = pendingDownloadMode {
                        recognitionModeRaw = mode.rawValue
                        previousRecognitionModeRaw = mode.rawValue
                    }
                    pendingDownloadMode = nil
                }
                Button("cancel", role: .cancel) {
                    pendingDownloadMode = nil
                }
            } message: {
                if let mode = pendingDownloadMode {
                    let sizeDesc = WhisperSpeechRecognitionService.downloadSizeDescription(for: mode)
                    Text(String(format: String(localized: "recognition_model_download_confirm_message"), sizeDesc))
                }
            }

            // 显示设置：仅当识别语言为「日语」时才显示
            if recognitionSourceLanguage == "ja" {
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
                } header: {
                    Text("display_settings")
                }
            }

            Section {
                Toggle(isOn: $translationEnabled) {
                    Label {
                        Text("translation_enabled_label").font(.subheadline)
                    } icon: {
                        Image(systemName: "text.bubble").foregroundStyle(.blue)
                    }
                }
                .onChange(of: translationEnabled) { _, isOn in
                    if isOn {
                        triggerTranslationLanguagePackDownloadAndShowNetworkHint()
                    }
                    HapticManager.shared.selection()
                }
                
                Picker(selection: $targetLanguageCode) {
                    ForEach(TranslationTargetLanguageOptions.allCodes, id: \.self) { code in
                        Text(TranslationTargetLanguageOptions.displayName(code: code, locale: locale)).tag(code)
                    }
                } label: {
                    Label {
                        Text("target_language").font(.subheadline)
                    } icon: {
                        Image(systemName: "globe").foregroundStyle(.blue)
                    }
                }
                .onChange(of: targetLanguageCode) { _, newValue in
                    let v = TranslationTargetLanguageOptions.normalizedCode(newValue)
                    targetLanguageCode = v
                    UserDefaults.standard.set(v, forKey: "targetLanguageCode")
                    HapticManager.shared.success()
                }
            } header: {
                Text("translation_settings")
            } footer: {
                Text(String(localized: LocalizedStringResource("translation_target_footer", locale: locale)))
            }
            .alert(String(localized: "translation_network_hint_title"), isPresented: $showTranslationNetworkHint) {
                Button("ok") { showTranslationNetworkHint = false }
            } message: {
                Text("translation_network_hint_message")
            }
                        
            Section {
                infoRow(title: "version", value: "1.0.0", icon: "info.circle", color: .secondary)
                infoRow(title: "engine", value: "Whisper (On-Device)", icon: "cpu", color: .secondary)
            } header: {
                Text("about")
            }

            Section {
                Button {
                    openURL(URL(string: "mailto:toshiki.tech.jp@gmail.com?subject=YomiPlay%20Feedback")!)
                } label: {
                    Label("settings_feedback_email", systemImage: "envelope")
                        .font(.subheadline)
                }

                Button {
                    showHelpSheet = true
                } label: {
                    Label("settings_help_center", systemImage: "questionmark.circle")
                        .font(.subheadline)
                }
            } header: {
                Text("settings_support_section")
            }

            Section {
                Button(role: .destructive) {
                    showClearCacheConfirm = true
                } label: {
                    Label("settings_clear_cache", systemImage: "trash")
                        .font(.subheadline)
                }
            } footer: {
                Text("settings_clear_cache_footer")
            }
            
            #if DEBUG
            Section {
                Toggle(isOn: Binding(
                    get: { subscription.debugSimulateProUser },
                    set: { subscription.debugSimulateProUser = $0 }
                )) {
                    Label("模拟 Pro 用户", systemImage: "crown.fill")
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Debug")
            } footer: {
                Text("开启后全应用显示 Pro 状态，用于测试导入页/设置页等 Pro 界面。仅 Debug 构建有效。")
            }
            #endif
        }
        .navigationTitle("settings")
        .sheet(isPresented: $showPaywall) {
            PaywallView(onDismiss: { showPaywall = false })
        }
        .sheet(isPresented: $showHelpSheet) {
            NavigationStack {
                HelpCenterView()
            }
        }
        .alert("settings_clear_cache", isPresented: $showClearCacheConfirm) {
            Button("cancel", role: .cancel) {}
            Button("settings_clear_cache_confirm", role: .destructive) {
                clearTemporaryCache()
            }
        } message: {
            Text("settings_clear_cache_message")
        }
        .alert("settings_clear_cache_result_title", isPresented: $showClearCacheResult) {
            Button("ok") {}
        } message: {
            Text(clearCacheResultMessage ?? "")
        }
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

    /// 按当前界面语言显示推荐模型名称，避免界面为英文时仍显示「标准」等中文
    private var recommendedModeDisplayName: String {
        let mode = WhisperSpeechRecognitionService.recommendedModeForDevice
        switch mode {
        case .tiny: return String(localized: LocalizedStringResource("recognition_mode_tiny", locale: locale))
        case .base: return String(localized: LocalizedStringResource("recognition_mode_base", locale: locale))
        case .small: return String(localized: LocalizedStringResource("recognition_mode_small", locale: locale))
        case .medium: return String(localized: LocalizedStringResource("recognition_mode_medium", locale: locale))
        case .large: return String(localized: LocalizedStringResource("recognition_mode_large", locale: locale))
        }
    }

    /// 用户打开「开启翻译」时：触发一次最小翻译以拉取语言包，然后提示允许网络
    private func triggerTranslationLanguagePackDownloadAndShowNetworkHint() {
        let targetLang = TranslationTargetLanguageOptions.resolvedStoredOrDefault()
        let segment = TranscriptSegment(startTime: 0, endTime: 0, originalText: "こんにちは")
        Task {
            _ = try? await TranslationService.shared.translateSegments(
                [segment],
                sourceLanguageCode: "ja",
                targetLanguageCode: targetLang
            )
            await MainActor.run {
                showTranslationNetworkHint = true
            }
        }
    }

    private func clearTemporaryCache() {
        let fm = FileManager.default
        var removedCount = 0
        var removedBytes: Int64 = 0

        do {
            let tempDir = fm.temporaryDirectory
            let tempFiles = try fm.contentsOfDirectory(
                at: tempDir,
                includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
                options: [.skipsHiddenFiles]
            )
            for file in tempFiles {
                if let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]),
                   values.isRegularFile == true {
                    removedBytes += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
                }
                try? fm.removeItem(at: file)
                removedCount += 1
            }

            let cacheDir = try fm.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            let cacheFiles = (try? fm.contentsOfDirectory(
                at: cacheDir,
                includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            for file in cacheFiles where file.lastPathComponent.lowercased().contains("yomiplay") {
                if let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]),
                   values.isRegularFile == true {
                    removedBytes += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
                }
                try? fm.removeItem(at: file)
                removedCount += 1
            }

            let mb = Double(removedBytes) / (1024 * 1024)
            clearCacheResultMessage = String(
                format: String(localized: LocalizedStringResource("settings_clear_cache_result_success", locale: locale)),
                removedCount,
                mb
            )
            showClearCacheResult = true
        } catch {
            clearCacheResultMessage = String(
                format: String(localized: LocalizedStringResource("settings_clear_cache_result_failed", locale: locale)),
                error.localizedDescription
            )
            showClearCacheResult = true
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

private struct HelpCenterView: View {
    var body: some View {
        List {
            Section("settings_help_faq_section") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("settings_help_q1").font(.subheadline).fontWeight(.semibold)
                    Text("settings_help_a1")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("settings_help_q2").font(.subheadline).fontWeight(.semibold)
                    Text("settings_help_a2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("settings_help_q3").font(.subheadline).fontWeight(.semibold)
                    Text("settings_help_a3")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("settings_help_about_section") {
                Text("settings_help_about_1")
                    .font(.subheadline)
                Text("settings_help_about_2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("settings_help_title")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 设置页头部（Free / Pro 动态状态）

private struct SettingsHeaderView: View {
    @Environment(\.locale) private var locale
    @Bindable var subscription: SubscriptionManager
    var onUpgradeTap: () -> Void = {}
    @State private var crownRotation: Double = 0
    
    private var quotaProgress: Double {
        let limit = subscription.freeQuotaLimitSeconds
        return limit > 0 ? min(1, Double(subscription.monthlyUsedSeconds) / Double(limit)) : 0
    }
    
    private static let quotaGradient = LinearGradient(
        colors: [.green, .orange],
        startPoint: .leading,
        endPoint: .trailing
    )
    
    private static let goldGradient = LinearGradient(
        colors: [Color(red: 0.95, green: 0.78, blue: 0.2), Color(red: 0.85, green: 0.6, blue: 0.1)],
        startPoint: .leading,
        endPoint: .trailing
    )
    
    private static let proBgGradient = LinearGradient(
        colors: [.purple.opacity(0.85), .blue.opacity(0.75)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    var body: some View {
        Group {
            if subscription.isProUser {
                proHeader
            } else {
                freeHeader
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 20)
    }
    
    // MARK: - Free 状态：柔和衬底 + 居中文字 + 彩色标题 + 配额进度条
    
    private static let freeTitleGradient = LinearGradient(
        colors: [.green, .blue],
        startPoint: .leading,
        endPoint: .trailing
    )
    
    private var freeHeader: some View {
        VStack(spacing: 12) {
            Text(String(localized: LocalizedStringResource("settings_header_free_title", locale: locale)))
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(Self.freeTitleGradient)
                .multilineTextAlignment(.center)
            
            Text(String(localized: LocalizedStringResource("settings_header_free_subtitle", locale: locale)))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            VStack(spacing: 10) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(.secondarySystemFill))
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Self.quotaGradient)
                            .frame(width: max(0, geo.size.width * quotaProgress))
                    }
                }
                .frame(height: 10)
                
                Text(String(format: String(localized: LocalizedStringResource("settings_header_free_quota_hint", locale: locale)), subscription.remainingFreeSeconds / 60))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity)

            Button(action: onUpgradeTap) {
                HStack(spacing: 6) {
                    Image(systemName: "crown.fill")
                    Text("settings_upgrade_button")
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [Color.green, Color.green.opacity(0.85)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
    }
    
    // MARK: - Pro 状态：紫蓝渐变 + 金色标题 + 皇冠动画
    
    private var proHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text(String(localized: LocalizedStringResource("settings_header_pro_title", locale: locale)))
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(Self.goldGradient)
                
                Image(systemName: "crown.fill")
                    .font(.title2)
                    .foregroundStyle(Self.goldGradient)
                    .rotationEffect(.degrees(crownRotation))
            }
            
            Text(String(localized: LocalizedStringResource("settings_header_pro_subtitle", locale: locale)))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.95))
            
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title3)
                    .foregroundStyle(.yellow)
                Text(expiryText)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Self.proBgGradient)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onAppear {
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                crownRotation = 8
            }
        }
    }
    
    private var expiryText: String {
        if let date = subscription.proExpirationDate {
            let f = DateFormatter()
            f.locale = locale
            f.dateStyle = .long
            f.timeStyle = .none
            let format = String(localized: LocalizedStringResource("settings_header_pro_expiry", locale: locale))
            return String(format: format, f.string(from: date))
        }
        return String(localized: LocalizedStringResource("settings_header_pro_expiry_lifetime", locale: locale))
    }
}

#Preview {
    SettingsView()
}
