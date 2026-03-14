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
    
    var body: some View {
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
    }
}

#Preview {
    ContentView()
}
