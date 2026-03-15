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
import UIKit

private enum HomeTab: Int, CaseIterable {
    case library = 0
    case importTab = 1
    case settings = 2
}

struct HomeView: View {
    @Binding var navigationPath: NavigationPath
    @Bindable var viewModel: HomeViewModel
    
    @State private var selectedTab: HomeTab = .library
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // 记录 (Library) タブ
            LibraryView(viewModel: viewModel, navigationPath: $navigationPath)
                .tabItem {
                    Label("saved_records", systemImage: "clock.fill")
                }
                .tag(HomeTab.library)
            
            // 导入 (Import) タブ
            ImportView(viewModel: viewModel)
                .navigationTitle("import")
                .tabItem {
                    Label("import", systemImage: "plus.circle.fill")
                }
                .tag(HomeTab.importTab)
            
            // 设置 (Settings) タブ
            SettingsView()
                .tabItem {
                    Label("settings", systemImage: "gearshape.fill")
                }
                .tag(HomeTab.settings)
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
                case .zip: return [.zip]
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
                case .zip:
                    // 必须在回调内立即获取安全作用域，否则选择器关闭后 URL 可能失效导致崩溃
                    guard url.startAccessingSecurityScopedResource() else {
                        viewModel.showErrorMessage(String(localized: "no_permission_to_access_the_file"))
                        return
                    }
                    viewModel.handleZipImport(url: url)
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
        .overlay {
            if viewModel.isLoadingVideo {
                loadingOverlay
            }
        }
        .overlay {
            if viewModel.isImportingZip || viewModel.zipImportSuccessInfo != nil {
                zipImportOverlay
            }
        }
        .onChange(of: viewModel.requestSwitchToLibraryTab) { _, shouldSwitch in
            if shouldSwitch {
                selectedTab = .library
                viewModel.requestSwitchToLibraryTab = false
            }
        }
        .onChange(of: viewModel.zipImportNavigateToFolderId) { _, folderId in
            if let id = folderId {
                navigationPath.append(AppDestination.folder(folderId: id))
                viewModel.zipImportNavigateToFolderId = nil
            }
        }
        .sheet(isPresented: $viewModel.showShareZipSheet, onDismiss: { viewModel.clearExportedZip() }) {
            if let url = viewModel.exportedZipURL {
                ShareSheet(activityItems: [url], onDismiss: { viewModel.clearExportedZip() })
            } else {
                Color.clear
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
    
    private var zipImportOverlay: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            VStack(spacing: 16) {
                if let info = viewModel.zipImportSuccessInfo {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)
                    Text(String(format: String(localized: "zip_import_success_format"), info.count, info.folderName))
                        .font(.headline)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                } else {
                    ProgressView().scaleEffect(1.5).tint(.orange)
                    Text(viewModel.zipImportProgressMessage).font(.headline).foregroundStyle(.white)
                }
            }
            .padding(32).background(RoundedRectangle(cornerRadius: 20).fill(.ultraThinMaterial))
        }
        .onChange(of: viewModel.zipImportSuccessInfo) { _, newInfo in
            guard newInfo != nil else { return }
            Task {
                try? await Task.sleep(for: .seconds(1.8))
                await MainActor.run { viewModel.zipImportSuccessInfo = nil }
            }
        }
    }
}

// MARK: - 分享 ZIP（系统分享面板）
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    var onDismiss: (() -> Void)?
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        vc.completionWithItemsHandler = { _, _, _, _ in onDismiss?() }
        return vc
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
