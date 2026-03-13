//
//  HomeView.swift
//  YomiPlay
//
//  メインタブコンテナ
//  インポート・履歴・設定の各タブを統合管理する
//

import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

struct HomeView: View {
    @Binding var navigationPath: NavigationPath
    @State private var viewModel = HomeViewModel()
    
    // タブの選択状態
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // 记录 (Library) タブ
            LibraryView(viewModel: viewModel, navigationPath: $navigationPath)
                .tabItem {
                    Label("saved_records", systemImage: "clock.fill")
                }
                .tag(0)
            
            // 导入 (Import) タブ
            ImportView(viewModel: viewModel)
                .navigationTitle("import")
                .tabItem {
                    Label("import", systemImage: "plus.circle.fill")
                }
                .tag(1)
            
            // 设置 (Settings) タブ
            SettingsView()
                .tabItem {
                    Label("settings", systemImage: "gearshape.fill")
                }
                .tag(2)
        }
        .accentColor(.green)
        // 共通のアラートやシートはここに残す
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
                navigationPath.append(AppDestination.player(documents: [doc], currentIndex: 0))
            }
        }
        .alert("error", isPresented: $viewModel.showError) { Button("ok") {} } message: { Text(viewModel.errorMessage ?? String(localized: "unknown_error")) }
        .alert("rename", isPresented: $viewModel.showRenameAlert) {
            TextField("enter_new_name", text: $viewModel.newTitle)
            Button("cancel", role: .cancel) { viewModel.documentToRename = nil }
            Button("save") { viewModel.confirmRename() }
        }
        .overlay {
            if viewModel.isLoadingVideo {
                loadingOverlay
            }
        }
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
}
