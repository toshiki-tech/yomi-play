//
//  ImportView.swift
//  YomiPlay
//
//  新規インポート画面
//

import SwiftUI
import PhotosUI

struct ImportView: View {
    @Environment(\.locale) private var locale
    @Bindable var viewModel: HomeViewModel
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var showPodcastSearchImport: Bool = false
    @State private var showURLImport: Bool = false
    private var subscription: SubscriptionManager { SubscriptionManager.shared }

    var body: some View {
        ZStack {
            mainBody
                .onChange(of: selectedVideoItem) { _, newValue in
                    if let item = newValue {
                        viewModel.handlePhotoPickerItem(item)
                        selectedVideoItem = nil
                    }
                }
            
            if viewModel.showSRTOption {
                optionsOverlay
                    .zIndex(1)
            }
        }
        .animation(.spring(duration: 0.3), value: viewModel.showSRTOption)
    }
    
    // MARK: - Subviews
    
    private var mainBody: some View {
        ScrollView {
            VStack(spacing: 32) {
                headerSection
                headerStatusSection
                VStack(spacing: 16) {
                    podcastSearchImportSection
                    urlImportSection
                    fileImportSection
                    photoLibrarySection
                    zipImportSection
                }
                Spacer()
            }
            .padding(20)
            .contentShape(Rectangle())
        }
        .background(Color(.systemBackground))
        .disabled(viewModel.showSRTOption)
        .animation(.easeInOut(duration: 0.35), value: subscription.isProUser)
    }

    /// 根据 isProUser 动态展示：免费 = 配额进度条 + 升级 Pro；Pro = 尊贵身份条 + 有效期
    private var headerStatusSection: some View {
        Group {
            if subscription.isProUser {
                proPrivilegeBar
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                freeQuotaCard
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeInOut(duration: 0.35), value: subscription.isProUser)
    }

    /// 免费用户：配额进度条（渐变色，剩余 <5 分钟变红）+ 右侧「升级 Pro」按钮
    private var freeQuotaCard: some View {
        let remainingMin = subscription.remainingFreeSeconds / 60
        let isLowQuota = remainingMin < 5
        let progress = subscription.freeQuotaLimitSeconds > 0
            ? Double(subscription.monthlyUsedSeconds) / Double(subscription.freeQuotaLimitSeconds)
            : 0.0
        let progressGradient = isLowQuota
            ? LinearGradient(colors: [.red, .orange], startPoint: .leading, endPoint: .trailing)
            : LinearGradient(colors: [.green, .green.opacity(0.7)], startPoint: .leading, endPoint: .trailing)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: LocalizedStringResource("monthly_free_quota", locale: locale)))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: String(localized: LocalizedStringResource("quota_progress_format", locale: locale)), subscription.monthlyUsedSeconds / 60, remainingMin))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                Button {
                    viewModel.showPaywall = true
                } label: {
                    Text("import_upgrade_pro")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.green))
                }
                .buttonStyle(.plain)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.primary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 5)
                        .fill(progressGradient)
                        .frame(width: max(0, geo.size.width * min(1, progress)))
                }
            }
            .frame(height: 8)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Pro 用户：尊贵身份条 —「无限识别特权已生效」+ 小字有效期
    private var proPrivilegeBar: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.subheadline)
                    .foregroundStyle(.yellow)
                Text("import_pro_privilege_active")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
            }
            Text(proExpiryText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }

    private var proExpiryText: String {
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
    
    private var optionsOverlay: some View {
        ZStack {
            // 背景のボカシ
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    viewModel.pendingAudioSource = nil
                    viewModel.showSRTOption = false
                }
            
            // 選択カード
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("home_subtitle_choice_title")
                        .font(.headline)
                    Text("home_subtitle_choice_message")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 8)
                
                VStack(spacing: 12) {
                    // AI音声認識
                    choiceCard(
                        title: "home_subtitle_choice_skip_button",
                        description: "use_ai_recognition",
                        image: "sparkles",
                        color: .green
                    ) {
                        viewModel.skipSRT()
                    }
                    
                    // SRTファイル
                    choiceCard(
                        title: "home_subtitle_choice_srt_button",
                        description: "import_standard_subtitles",
                        image: "doc.text.fill",
                        color: .blue
                    ) {
                        viewModel.fileImportMode = .srt
                        viewModel.isFileImporterPresented = true
                    }
                    
                    // YOMIファイル
                    choiceCard(
                        title: "home_subtitle_choice_yomi_button",
                        description: "import_formatted_yomi",
                        image: "character.bubble.fill",
                        color: .orange
                    ) {
                        viewModel.fileImportMode = .yomi
                        viewModel.isFileImporterPresented = true
                    }
                }
                
                Button("cancel") {
                    viewModel.pendingAudioSource = nil
                    viewModel.showSRTOption = false
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
            )
            .padding(.horizontal, 32)
            .transition(.scale.combined(with: .opacity))
        }
    }
    
    private func choiceCard(title: LocalizedStringKey, description: LocalizedStringKey, image: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.1))
                        .frame(width: 40, height: 40)
                    Image(systemName: image)
                        .foregroundStyle(color)
                        .font(.system(size: 18, weight: .semibold))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground).opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var fileImportSection: some View {
        Button {
            viewModel.fileImportMode = .audioVideo
            viewModel.isFileImporterPresented = true
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.blue.opacity(0.1))
                    Image(systemName: "folder.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                }
                .frame(width: 50, height: 50)
                VStack(alignment: .leading, spacing: 4) {
                    Text("select_from_files").font(.headline)
                    HStack(spacing: 4) {
                        Text("mp3, m4a, wav,")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 2) {
                            Text("mp4")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Image(systemName: "crown.fill")
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                        }
                        Text(",")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 2) {
                            Text("mov")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Image(systemName: "crown.fill")
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
        }
        .buttonStyle(.plain)
    }
    
    private var zipImportSection: some View {
        Button {
            if subscription.isProUser {
                viewModel.fileImportMode = .zip
                viewModel.isFileImporterPresented = true
            } else {
                viewModel.showPaywall = true
            }
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.orange.opacity(0.1))
                    Image(systemName: "doc.zipper")
                        .font(.title2)
                        .foregroundStyle(.orange)
                }
                .frame(width: 50, height: 50)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("import_from_zip").font(.headline)
                        Image(systemName: "crown.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                        if !subscription.isProUser {
                            Text("Pro").font(.caption2).fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.orange))
                        }
                    }
                    Text("import_zip_description").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
        }
        .buttonStyle(.plain)
    }
    
    private var podcastSearchImportSection: some View {
        Button {
            showPodcastSearchImport = true
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.pink.opacity(0.1))
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.title2)
                        .foregroundStyle(.pink)
                }
                .frame(width: 50, height: 50)
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: LocalizedStringResource("import_from_podcast", locale: locale)))
                        .font(.headline)
                    Text(String(localized: LocalizedStringResource("import_podcast_description", locale: locale)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showPodcastSearchImport) {
            PodcastSearchImportView(viewModel: viewModel, onDismiss: { showPodcastSearchImport = false })
        }
    }

    private var urlImportSection: some View {
        Button {
            showURLImport = true
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.green.opacity(0.1))
                    Image(systemName: "link")
                        .font(.title2)
                        .foregroundStyle(.green)
                }
                .frame(width: 50, height: 50)
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: LocalizedStringResource("load_from_url", locale: locale)))
                        .font(.headline)
                    Text(String(localized: LocalizedStringResource("podcast_audio_import_hint", locale: locale)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showURLImport) {
            URLImportView(viewModel: viewModel, onDismiss: { showURLImport = false })
        }
    }
    
    private var photoLibrarySection: some View {
        Group {
            if subscription.isProUser {
                PhotosPicker(selection: $selectedVideoItem, matching: .videos) {
                    photoLibraryRowContent
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    viewModel.showPaywall = true
                } label: {
                    photoLibraryRowContent
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    /// 从相册选择视频的行内容（Pro / 非 Pro 共用 UI）
    private var photoLibraryRowContent: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.purple.opacity(0.1))
                Image(systemName: "video.fill")
                    .font(.title2)
                    .foregroundStyle(.purple)
            }
            .frame(width: 50, height: 50)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("select_from_photo_library").font(.headline)
                    Image(systemName: "crown.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                    if !subscription.isProUser {
                        Text("Pro").font(.caption2).fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange))
                    }
                }
                Text("video_files_from_camera_roll")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }
    
    // MARK: - 播客搜索导入
    
    private struct PodcastSearchImportView: View {
        @Environment(\.locale) private var locale
        @Bindable var viewModel: HomeViewModel
        let onDismiss: () -> Void
        private static let podcastSearchHistoryKey = "podcastSearchHistoryTerms"
        private static let maxPodcastSearchHistoryCount = 6
        @State private var searchText = ""
        @State private var searchHistory: [String] = []
        @State private var firstSuccessfulSearchTerm: String?
        @State private var isSearching = false
        @State private var searchResults: [PodcastSearchResult] = []
        @State private var searchError: String?
        @State private var selectedPodcast: PodcastSearchResult?
        @State private var episodes: [PodcastEpisode] = []
        @State private var isLoadingEpisodes = false
        @State private var episodesError: String?
        @State private var showEpisodeQuotaAlert: Bool = false
        @State private var overQuotaEpisodeTitle: String = ""
        @FocusState private var isSearchFocused: Bool

        var body: some View {
            NavigationStack {
                Group {
                    if let podcast = selectedPodcast {
                        episodeListView(podcast: podcast)
                    } else {
                        mainInputView
                    }
                }
                .navigationTitle(selectedPodcast != nil ? selectedPodcast!.name : String(localized: LocalizedStringResource("import_from_podcast", locale: locale)))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        if selectedPodcast != nil {
                            Button {
                                selectedPodcast = nil
                                episodes = []
                                episodesError = nil
                            } label: {
                                Image(systemName: "chevron.left")
                                Text("back")
                            }
                        } else {
                            Button("close") { onDismiss() }
                        }
                    }
                }
            }
            .alert("podcast_episode_over_quota_title", isPresented: $showEpisodeQuotaAlert) {
                Button("import_upgrade_pro") {
                    viewModel.showPaywall = true
                }
                Button("cancel", role: .cancel) {}
            } message: {
                Text(String(
                    format: String(localized: LocalizedStringResource("podcast_episode_over_quota_message", locale: locale)),
                    overQuotaEpisodeTitle
                ))
            }
            .onAppear {
                loadSearchHistory()
            }
        }

        /// 首页：播客搜索
        private var mainInputView: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // 搜索播客节目
                    VStack(alignment: .leading, spacing: 10) {
                        searchViewContent
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
        }

        private var searchViewContent: some View {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "text.magnifyingglass")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("podcast_search_hint")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    if shouldShowFullGuidance {
                        Text(String(
                            format: String(localized: LocalizedStringResource("podcast_search_example_hint_format", locale: locale)),
                            currentSearchExample
                        ))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 12)

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("podcast_search_placeholder", text: $searchText)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { runSearch() }
                        .focused($isSearchFocused)
                    if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button {
                            searchText = ""
                            searchResults = []
                            searchError = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        runSearch()
                    } label: {
                        if isSearching {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.forward.circle.fill")
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(searchText.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(.secondarySystemBackground))
                )

                if !searchHistory.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("podcast_search_history_title")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("podcast_search_history_clear") {
                                clearSearchHistory()
                            }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(searchHistory, id: \.self) { term in
                                    Button {
                                        searchText = term
                                        runSearch()
                                    } label: {
                                        Text(term)
                                            .font(.caption)
                                            .lineLimit(1)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(
                                                Capsule()
                                                    .fill(Color(.secondarySystemBackground))
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                if let err = searchError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                if isSearching && searchResults.isEmpty {
                    ProgressView()
                        .padding(.vertical, 20)
                } else if searchResults.isEmpty && !searchText.isEmpty && !isSearching {
                    Text("podcast_no_results").font(.subheadline).foregroundStyle(.secondary)
                        .padding(.vertical, 20)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(searchResults) { podcast in
                            Button {
                                selectedPodcast = podcast
                                loadEpisodes(for: podcast)
                            } label: {
                                HStack(spacing: 12) {
                                    if let url = podcast.artworkURL {
                                        AsyncImage(url: url) { img in
                                            img.resizable().aspectRatio(contentMode: .fill)
                                        } placeholder: {
                                            Color.gray.opacity(0.2)
                                        }
                                        .frame(width: 56, height: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(podcast.name).font(.headline).lineLimit(2)
                                        Text(podcast.artistName).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }

        private func episodeListView(podcast: PodcastSearchResult) -> some View {
            Group {
                if isLoadingEpisodes {
                    VStack(spacing: 12) {
                        Spacer()
                        ProgressView()
                        Text("podcast_loading_episodes").font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                    }
                } else if let err = episodesError {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "exclamationmark.triangle").font(.title).foregroundStyle(.orange)
                        Text(err).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
                        Spacer()
                    }
                } else if episodes.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Text("podcast_no_episodes").font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                    }
                } else {
                    List(episodes) { ep in
                        Button {
                            handleEpisodeTap(ep)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ep.title).font(.subheadline).lineLimit(2)
                                HStack(spacing: 8) {
                                    if let date = ep.pubDate {
                                        Text(date, style: .date)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    if let seconds = ep.durationSeconds, seconds > 0 {
                                        Text(formatDuration(seconds))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .monospacedDigit()
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }

        private func formatDuration(_ totalSeconds: Int) -> String {
            let s = max(0, totalSeconds)
            let h = s / 3600
            let m = (s % 3600) / 60
            let sec = s % 60
            if h > 0 {
                return String(format: "%d:%02d:%02d", h, m, sec)
            } else {
                return String(format: "%d:%02d", m, sec)
            }
        }

        private func runSearch() {
            let term = searchText.trimmingCharacters(in: .whitespaces)
            guard !term.isEmpty else { return }
            searchError = nil
            isSearching = true
            Task {
                do {
                    let results = try await PodcastSearchService.search(term: term)
                    await MainActor.run {
                        searchResults = results
                        if !results.isEmpty {
                            addSearchHistory(term)
                            if firstSuccessfulSearchTerm == nil {
                                firstSuccessfulSearchTerm = term
                            }
                        }
                        isSearching = false
                    }
                } catch {
                    await MainActor.run {
                        searchError = error.localizedDescription
                        searchResults = []
                        isSearching = false
                    }
                }
            }
        }

        private var currentSearchExample: String {
            if let firstSuccessfulSearchTerm, !firstSuccessfulSearchTerm.isEmpty {
                return firstSuccessfulSearchTerm
            }
            return String(localized: LocalizedStringResource("podcast_search_example_default", locale: locale))
        }

        private var shouldShowFullGuidance: Bool {
            firstSuccessfulSearchTerm == nil && searchHistory.isEmpty
        }

        private func loadSearchHistory() {
            let terms = UserDefaults.standard.array(forKey: Self.podcastSearchHistoryKey) as? [String] ?? []
            searchHistory = terms.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if firstSuccessfulSearchTerm == nil {
                firstSuccessfulSearchTerm = searchHistory.first
            }
        }

        private func addSearchHistory(_ term: String) {
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            var updated = searchHistory.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
            updated.insert(trimmed, at: 0)
            if updated.count > Self.maxPodcastSearchHistoryCount {
                updated = Array(updated.prefix(Self.maxPodcastSearchHistoryCount))
            }
            searchHistory = updated
            UserDefaults.standard.set(updated, forKey: Self.podcastSearchHistoryKey)
        }

        private func clearSearchHistory() {
            searchHistory = []
            UserDefaults.standard.removeObject(forKey: Self.podcastSearchHistoryKey)
        }

        private func loadEpisodes(for podcast: PodcastSearchResult) {
            episodes = []
            episodesError = nil
            isLoadingEpisodes = true
            Task {
                do {
                    let list = try await PodcastSearchService.fetchEpisodes(feedURL: podcast.feedURL)
                    await MainActor.run {
                        episodes = list
                        isLoadingEpisodes = false
                    }
                } catch {
                    await MainActor.run {
                        episodesError = error.localizedDescription
                        isLoadingEpisodes = false
                    }
                }
            }
        }

        private func handleEpisodeTap(_ ep: PodcastEpisode) {
            if shouldBlockByQuota(ep) {
                overQuotaEpisodeTitle = ep.title
                showEpisodeQuotaAlert = true
                return
            }
            onDismiss()
            viewModel.startImportFromURL(ep.audioURL, title: ep.title)
        }

        private func shouldBlockByQuota(_ ep: PodcastEpisode) -> Bool {
            if SubscriptionManager.shared.isProUser { return false }
            guard let seconds = ep.durationSeconds, seconds > 0 else { return false }
            return !SubscriptionManager.shared.canUseRecognitionSeconds(seconds)
        }
    }

    // MARK: - URL 导入

    private struct URLImportView: View {
        @Environment(\.locale) private var locale
        @Bindable var viewModel: HomeViewModel
        let onDismiss: () -> Void

        @State private var urlInputText = ""
        @State private var urlImportError: String?
        @FocusState private var isUrlFieldFocused: Bool
        private var isURLInputEmpty: Bool {
            urlInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "link")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("podcast_audio_import_hint")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                            Text("podcast_url_unsupported_hint")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(.secondarySystemBackground))
                        )

                        VStack(alignment: .leading, spacing: 10) {
                            Text("paste_url_section_title")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            TextEditor(text: $urlInputText)
                                .frame(minHeight: 120, maxHeight: 180)
                                .padding(10)
                                .scrollContentBackground(.hidden)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.secondarySystemBackground))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(isUrlFieldFocused ? Color.green : Color.clear, lineWidth: 2)
                                )
                                .focused($isUrlFieldFocused)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)

                            if let err = urlImportError {
                                Text(err)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(.tertiarySystemBackground))
                        )

                        Button {
                            importFromPastedURL()
                        } label: {
                            Label("import_from_link", systemImage: "arrow.down.circle.fill")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .disabled(isURLInputEmpty)
                    }
                    .padding()
                }
                .navigationTitle(String(localized: LocalizedStringResource("load_from_url", locale: locale)))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("close") { onDismiss() }
                    }
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        isUrlFieldFocused = true
                    }
                }
            }
        }

        private func importFromPastedURL() {
            let trimmed = urlInputText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return }
            let firstLine = trimmed.split(separator: "\n").first.map(String.init) ?? trimmed
            guard let url = URL(string: firstLine), url.scheme != nil else {
                urlImportError = String(localized: "invalid_url_hint")
                return
            }
            urlImportError = nil
            let title = url.deletingPathExtension().lastPathComponent
            onDismiss()
            viewModel.startImportFromURL(
                url,
                title: (title.isEmpty || title == "/") ? "URL" : title
            )
        }
    }

    private static let crownGradient = LinearGradient(
        colors: [Color(red: 0.95, green: 0.78, blue: 0.2), Color(red: 0.85, green: 0.6, blue: 0.1)],
        startPoint: .top,
        endPoint: .bottom
    )

    private var headerSection: some View {
        VStack(spacing: 14) {
            // 更贴近“学习内容”语义的图标：书本 + 波形
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 96, height: 56)
                HStack(spacing: 6) {
                    // Image(systemName: "book.closed.fill")
                    //     .font(.system(size: 26, weight: .semibold))
                    //     .foregroundStyle(Color.accentColor)
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 36, weight: .regular))
                        .foregroundStyle(.linearGradient(colors: [.green, .green.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
            }

            VStack(spacing: 6) {
                Text("YomiPlay")
                    .font(.title)
                    .fontWeight(.bold)

                Text(String(localized: LocalizedStringResource("onboarding_tagline", locale: locale)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }
}
