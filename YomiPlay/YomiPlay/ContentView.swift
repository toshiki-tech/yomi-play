//
//  ContentView.swift
//  YomiPlay
//
//  アプリのルートビュー
//  NavigationStackベースのナビゲーションを提供する
//

import SwiftUI

// MARK: - ナビゲーション先の定義

/// ナビゲーション先を表す列挙型
enum AppDestination: Hashable {
    case processing(AudioSource)
    case player(documents: [TranscriptDocument], currentIndex: Int)
    /// フォルダ内一覧（nil = 未分组）
    case folder(folderId: UUID?)
}

// MARK: - ルートビュー

/// アプリのルートビュー。NavigationStackとNavigationPathを管理する
struct ContentView: View {
    @State private var navigationPath = NavigationPath()
    @State private var homeViewModel = HomeViewModel()
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding: Bool = false
    
    var body: some View {
        Group {
            if hasSeenOnboarding {
                mainShell
            } else {
                OnboardingView {
                    hasSeenOnboarding = true
                }
            }
        }
    }

    private var mainShell: some View {
        NavigationStack(path: $navigationPath) {
            HomeView(navigationPath: $navigationPath, viewModel: homeViewModel)
                .navigationDestination(for: AppDestination.self) { destination in
                    switch destination {
                    case .processing(let source):
                        ProcessingView(
                            audioSource: source,
                            navigationPath: $navigationPath
                        )
                    case .player(let documents, let currentIndex):
                        PlayerView(
                            documents: documents,
                            currentIndex: currentIndex,
                            navigationPath: $navigationPath
                        )
                    case .folder(let folderId):
                        FolderContentView(
                            viewModel: homeViewModel,
                            folderId: folderId,
                            navigationPath: $navigationPath
                        )
                    }
                }
        }
        .tint(.green)
        // 重命名弹窗放在导航栈之上，避免在分组内左滑重命名时被当前页遮挡
        .alert("rename", isPresented: Binding(
            get: { homeViewModel.showRenameAlert },
            set: { homeViewModel.showRenameAlert = $0 }
        )) {
            TextField("enter_new_name", text: Binding(
                get: { homeViewModel.newTitle },
                set: { homeViewModel.newTitle = $0 }
            ))
            Button("cancel", role: .cancel) { homeViewModel.documentToRename = nil }
            Button("save") { homeViewModel.confirmRename() }
        }
        .alert("rename_folder", isPresented: Binding(
            get: { homeViewModel.showFolderRenameAlert },
            set: { homeViewModel.showFolderRenameAlert = $0 }
        )) {
            TextField("folder_name", text: Binding(
                get: { homeViewModel.newFolderName },
                set: { homeViewModel.newFolderName = $0 }
            ))
            Button("cancel", role: .cancel) { homeViewModel.folderToRename = nil }
            Button("save") { homeViewModel.confirmFolderRename() }
                .disabled(homeViewModel.newFolderName.trimmingCharacters(in: .whitespaces).isEmpty)
        } message: {
            Text("rename_folder_message")
        }
    }
}

#Preview {
    ContentView()
}
