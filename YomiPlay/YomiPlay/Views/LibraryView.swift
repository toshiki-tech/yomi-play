//
//  LibraryView.swift
//  YomiPlay
//
//  保存済みドキュメント一覧画面
//

import SwiftUI

struct LibraryView: View {
    @Bindable var viewModel: HomeViewModel
    @Binding var navigationPath: NavigationPath
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // 検索・フィルタリングヘッダー
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("search_records", text: $viewModel.searchText)
                            .textFieldStyle(.plain)
                            .autocorrectionDisabled()
                            .focused($isSearchFocused)
                        
                        if !viewModel.searchText.isEmpty {
                            Button { viewModel.searchText = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.quaternarySystemFill)))
                    
                    Menu {
                        ForEach(DocumentSortOrder.allCases, id: \.self) { order in
                            Button {
                                viewModel.sortOrder = order
                            } label: {
                                HStack {
                                    Text(order.displayName)
                                    if viewModel.sortOrder == order {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.title3)
                            .foregroundStyle(.green)
                    }
                }
                .padding(.horizontal, 16)
            }
            .background(Color(.systemBackground))
            Divider()
            
            if viewModel.hasNoSavedDocuments {
                emptyStateView
            } else if viewModel.filteredDocuments.isEmpty {
                noResultsView
            } else {
                List {
                    ForEach(viewModel.filteredDocuments) { doc in
                        Button {
                            HapticManager.shared.impact(style: .light)
                            let docs = viewModel.filteredDocuments
                            if let index = docs.firstIndex(of: doc) {
                                navigationPath.append(AppDestination.player(documents: docs, currentIndex: index))
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(doc.source.title)
                                    .font(.headline)
                                    .lineLimit(1)
                                
                                HStack {
                                    Text("\(doc.segments.count) \("segments")")
                                    Text("•")
                                    Text(formatDate(doc.createdAt))
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RecordRowButtonStyle())
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                // 左滑删除：直接删除记录（不再弹出确认对话框）
                                viewModel.deleteDocument(doc)
                            } label: {
                                Label("delete", systemImage: "trash")
                            }
                            
                            Button {
                                viewModel.startRenaming(doc)
                            } label: {
                                Label("rename", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollDismissesKeyboard(.immediately)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            isSearchFocused = false
        }
        .navigationTitle("saved_records")
        .onAppear { viewModel.loadSavedDocuments() }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "doc.plaintext")
                .font(.system(size: 80))
                .foregroundStyle(.secondary.opacity(0.3))
            
            VStack(spacing: 8) {
                Text("no_records_yet")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("import_audio_video_to_start")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Spacer()
            Spacer()
        }
    }
    
    private var noResultsView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("no_matching_records")
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
}

/// 記録行専用のボタンラベルスタイル（即時フィードバック用）
struct RecordRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color(.systemFill) : Color.clear)
            .contentShape(Rectangle())
    }
}
