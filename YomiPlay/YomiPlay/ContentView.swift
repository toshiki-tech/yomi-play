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
}

// MARK: - ルートビュー

/// アプリのルートビュー。NavigationStackとNavigationPathを管理する
struct ContentView: View {
    @State private var navigationPath = NavigationPath()
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            HomeView(navigationPath: $navigationPath)
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
                    }
                }
        }
        .tint(.green)
    }
}

#Preview {
    ContentView()
}
