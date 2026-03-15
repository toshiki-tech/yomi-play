//
//  ImportView.swift
//  YomiPlay
//
//  新規インポート画面
//

import SwiftUI
import PhotosUI

struct ImportView: View {
    @Bindable var viewModel: HomeViewModel
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var showPodcastImport: Bool = false
    
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
                
                VStack(spacing: 16) {
                    podcastImportSection
                    photoLibrarySection
                    fileImportSection
                    zipImportSection
                }
                
                Spacer()
            }
            .padding(20)
            .contentShape(Rectangle())
        }
        .background(Color(.systemBackground))
        .disabled(viewModel.showSRTOption) // 選択中は背面を操作不可にする
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
                    Text("mp3, m4a, wav, mp4, mov").font(.caption).foregroundStyle(.secondary)
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
            viewModel.fileImportMode = .zip
            viewModel.isFileImporterPresented = true
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
                    Text("import_from_zip").font(.headline)
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
    
    private var podcastImportSection: some View {
        Button {
            showPodcastImport = true
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
                    Text("import_from_podcast_or_url").font(.headline)
                    Text("import_podcast_or_url_description").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showPodcastImport) {
            PodcastImportView(viewModel: viewModel, onDismiss: { showPodcastImport = false })
        }
    }
    
    private var photoLibrarySection: some View {
        PhotosPicker(selection: $selectedVideoItem, matching: .videos) {
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
                    Text("select_from_photo_library").font(.headline)
                    Text("video_files_from_camera_roll").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - 播客或URL导入（搜索播客 + 直接粘贴链接）
    
    private struct PodcastImportView: View {
        @Bindable var viewModel: HomeViewModel
        let onDismiss: () -> Void
        @State private var urlInputText = ""
        @State private var urlImportError: String?
        @State private var searchText = ""
        @State private var isSearching = false
        @State private var searchResults: [PodcastSearchResult] = []
        @State private var searchError: String?
        @State private var selectedPodcast: PodcastSearchResult?
        @State private var episodes: [PodcastEpisode] = []
        @State private var isLoadingEpisodes = false
        @State private var episodesError: String?
        @FocusState private var isSearchFocused: Bool
        @FocusState private var isUrlFieldFocused: Bool

        var body: some View {
            NavigationStack {
                Group {
                    if let podcast = selectedPodcast {
                        episodeListView(podcast: podcast)
                    } else {
                        mainInputView
                    }
                }
                .navigationTitle(selectedPodcast != nil ? selectedPodcast!.name : String(localized: "import_from_podcast_or_url"))
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
        }

        /// 首页：URL 输入区 + 播客搜索
        private var mainInputView: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // URL 输入区
                    VStack(alignment: .leading, spacing: 10) {
                        Label("paste_url_section_title", systemImage: "link")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $urlInputText)
                            .frame(minHeight: 80, maxHeight: 120)
                            .padding(10)
                            .scrollContentBackground(.hidden)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isUrlFieldFocused ? Color.green : Color.clear, lineWidth: 2))
                            .focused($isUrlFieldFocused)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        if let err = urlImportError {
                            Text(err).font(.caption).foregroundStyle(.red)
                        }
                        Button {
                            importFromPastedURL()
                        } label: {
                            Label("import_from_link", systemImage: "arrow.down.circle.fill")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .disabled(urlInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground).opacity(0.6)))

                    Divider()
                        .padding(.vertical, 4)

                    // 搜索播客节目
                    VStack(alignment: .leading, spacing: 10) {
                        Text("podcast_search_section_title")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        searchViewContent
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
        }

        private var searchViewContent: some View {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    TextField("podcast_search_placeholder", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { runSearch() }
                        .focused($isSearchFocused)
                    Button {
                        runSearch()
                    } label: {
                        if isSearching {
                            ProgressView()
                                .scaleEffect(0.9)
                        } else {
                            Image(systemName: "magnifyingglass")
                        }
                    }
                    .disabled(searchText.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
                }
                .padding(.horizontal)

                if let err = searchError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                if isSearching && searchResults.isEmpty {
                    ProgressView()
                    Text("podcast_searching").font(.subheadline).foregroundStyle(.secondary)
                        .padding(.vertical, 20)
                } else if searchResults.isEmpty && !searchText.isEmpty && !isSearching {
                    Text("podcast_no_results").font(.subheadline).foregroundStyle(.secondary)
                        .padding(.vertical, 20)
                } else if searchResults.isEmpty {
                    Text("podcast_search_hint").font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
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
                }
            }
        }

        private func importFromPastedURL() {
            let trimmed = urlInputText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return }
            // 多行时取第一行
            let firstLine = trimmed.split(separator: "\n").first.map(String.init) ?? trimmed
            guard let url = URL(string: firstLine), url.scheme != nil else {
                urlImportError = String(localized: "invalid_url_hint")
                return
            }
            urlImportError = nil
            let title = url.deletingPathExtension().lastPathComponent
            onDismiss() // 先关闭播客页，再在导入页显示「是否附带字幕」选择
            if title.isEmpty || title == "/" {
                viewModel.startImportFromURL(url, title: "URL")
            } else {
                viewModel.startImportFromURL(url, title: title)
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
                            onDismiss()
                            viewModel.startImportFromURL(ep.audioURL, title: ep.title)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ep.title).font(.subheadline).lineLimit(2)
                                if let date = ep.pubDate {
                                    Text(date, style: .date)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
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
    }

    private var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.linearGradient(colors: [.green, .green.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .symbolRenderingMode(.hierarchical)
            
            VStack(spacing: 4) {
                Text("YomiPlay").font(.largeTitle).fontWeight(.bold)
                Text("Japanese Learning & Subtitles").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 20)
    }
}
