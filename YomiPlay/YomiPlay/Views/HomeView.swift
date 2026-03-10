//
//  HomeView.swift
//  YomiPlay
//
//  ホーム画面
//

import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

struct HomeView: View {
    @Binding var navigationPath: NavigationPath
    @State private var viewModel = HomeViewModel()
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var documentToDelete: TranscriptDocument?
    
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    actionSection
                    urlInputSection
                    
                    // 保存済み記録リスト
                    savedRecordsSection
                    
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.loadSavedDocuments() }
        .fileImporter(
            isPresented: $viewModel.isFileImporterPresented,
            allowedContentTypes: {
                switch viewModel.fileImportMode {
                case .audioVideo: return [.mp3, .mpeg4Audio, .wav, .aiff, .audio, .mpeg4Movie, .quickTimeMovie, .movie, .video]
                case .srt: return [.plainText]
                case .yomi: return [.yomiDocument, .json]
                }
            }(),
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                switch viewModel.fileImportMode {
                case .audioVideo:
                    viewModel.handleFileSelected(result: .success(url))
                case .srt:
                    viewModel.attachSRT(url: url)
                case .yomi:
                    viewModel.attachYomi(url: url)
                }
            }
        }
        .onChange(of: selectedVideoItem) { _, newValue in
            if let item = newValue {
                viewModel.handlePhotoPickerItem(item)
                selectedVideoItem = nil
            }
        }
        .onChange(of: viewModel.navigateToProcessing) { _, shouldNavigate in
            if shouldNavigate, let source = viewModel.selectedAudioSource {
                viewModel.navigateToProcessing = false
                navigationPath.append(AppDestination.processing(source))
            }
        }
        .onChange(of: viewModel.navigateToPlayer) { _, shouldNavigate in
            if shouldNavigate, let doc = viewModel.navigateToPlayerDocument {
                viewModel.navigateToPlayer = false
                viewModel.navigateToPlayerDocument = nil
                navigationPath.append(AppDestination.player(doc))
            }
        }
        .alert("error", isPresented: $viewModel.showError) { Button("ok") {} } message: { Text(viewModel.errorMessage ?? String(localized: "unknown_error")) }
        .alert("rename", isPresented: $viewModel.showRenameAlert) {
            TextField("enter_new_name", text: $viewModel.newTitle)
            Button("cancel", role: .cancel) { viewModel.documentToRename = nil }
            Button("save") { viewModel.confirmRename() }
        }
        .confirmationDialog("delete_this_record", isPresented: Binding(
            get: { documentToDelete != nil },
            set: { if !$0 { documentToDelete = nil } }
        )) {
            Button("delete", role: .destructive) {
                if let doc = documentToDelete {
                    viewModel.deleteDocument(doc)
                    documentToDelete = nil
                }
            }
            Button("cancel", role: .cancel) { documentToDelete = nil }
        } message: {
            Text("this_action_cannot_be_undone")
        }
        .confirmationDialog(String(localized: "home_subtitle_choice_title"), isPresented: $viewModel.showSRTOption) {
            Button(String(localized: "home_subtitle_choice_srt_button")) {
                viewModel.fileImportMode = .srt
                viewModel.isFileImporterPresented = true
            }
            Button(String(localized: "home_subtitle_choice_yomi_button")) {
                viewModel.fileImportMode = .yomi
                viewModel.isFileImporterPresented = true
            }
            Button(String(localized: "home_subtitle_choice_skip_button")) { viewModel.skipSRT() }
            Button("cancel", role: .cancel) { viewModel.pendingAudioSource = nil }
        } message: {
            Text("home_subtitle_choice_message")
        }
        .overlay { if viewModel.isLoadingVideo { loadingOverlay } }
    }
    
    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView().scaleEffect(1.5).tint(.green)
                Text("loading_video").font(.headline).foregroundStyle(.white)
            }
            .padding(32).background(RoundedRectangle(cornerRadius: 20).fill(.ultraThinMaterial))
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.linearGradient(colors: [.green, .green.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .symbolRenderingMode(.hierarchical)
            Text("YomiPlay").font(.largeTitle).fontWeight(.bold)
        }
        .padding(.top, 12)
    }
    
    private var actionSection: some View {
        VStack(spacing: 12) {
            Button { viewModel.fileImportMode = .audioVideo; viewModel.isFileImporterPresented = true } label: {
                HStack(spacing: 14) {
                    Image(systemName: "folder.fill").font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("select_from_files").font(.headline)
                        Text(verbatim: "mp3 / m4a / wav / mp4 / mov").font(.caption).opacity(0.7)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").opacity(0.5)
                }
                .padding(16).foregroundStyle(.white).background(RoundedRectangle(cornerRadius: 14).fill(LinearGradient(colors: [.green.opacity(0.8), .green.opacity(0.6)], startPoint: .leading, endPoint: .trailing)))
            }
            PhotosPicker(selection: $selectedVideoItem, matching: .videos) {
                HStack(spacing: 14) {
                    Image(systemName: "photo.on.rectangle.angled").font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("select_from_photo_library").font(.headline)
                        Text("video_files_from_camera_roll").font(.caption).opacity(0.7)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").opacity(0.5)
                }
                .padding(16).foregroundStyle(.white).background(RoundedRectangle(cornerRadius: 14).fill(LinearGradient(colors: [.green.opacity(0.6), .green.opacity(0.4)], startPoint: .leading, endPoint: .trailing)))
            }
        }
    }
    
    private var urlInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("load_from_url", systemImage: "link").font(.headline)
            HStack(spacing: 12) {
                TextField("enter_audio_video_url", text: $viewModel.urlText).textFieldStyle(.roundedBorder).keyboardType(.URL)
                Button { viewModel.loadFromURL() } label: {
                    Image(systemName: "arrow.down.circle.fill").font(.title2).foregroundStyle(.green)
                }
                .disabled(viewModel.urlText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16).background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
    }
    
    private var savedRecordsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("saved_records", systemImage: "clock.arrow.circlepath").font(.headline)
                Spacer()
                Menu {
                    ForEach(DocumentSortOrder.allCases, id: \.self) { order in
                        Button(viewModel.sortOrder == order ? "✓ \(order.displayName)" : order.displayName) {
                            viewModel.sortOrder = order
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            
            // 検索バー
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("search_records", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
            
            if viewModel.hasNoSavedDocuments {
                emptyStateGuide
            } else if viewModel.filteredDocuments.isEmpty {
                Text("no_matching_records")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            } else {
                ForEach(viewModel.filteredDocuments) { doc in
                    savedRecordRow(doc)
                }
            }
        }
    }
    
    private var emptyStateGuide: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.8))
            Text("no_records_yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("从文件、相册或URL\n导入音频/视频来创建字幕")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
    }
    
    private func savedRecordRow(_ doc: TranscriptDocument) -> some View {
        Button {
            navigationPath.append(AppDestination.player(doc))
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "doc.text.fill").font(.title2).foregroundStyle(.green).frame(width: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(doc.source.title).font(.subheadline).fontWeight(.medium).foregroundStyle(.primary).lineLimit(1)
                    Text(verbatim: "\(doc.segments.count) " + String(localized: "segments") + " • " + formatDate(doc.createdAt)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                
                Menu {
                    Button { viewModel.startRenaming(doc) } label: {
                        Label("rename", systemImage: "pencil")
                    }
                    Button(role: .destructive) { documentToDelete = doc } label: {
                        Label("delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(.secondary).padding(4)
                }
                .buttonStyle(.plain)
            }
            .padding(14).background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
        }
        .buttonStyle(.plain)
    }
    
    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM/dd HH:mm"
        return f.string(from: date)
    }
}
