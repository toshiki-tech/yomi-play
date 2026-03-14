//
//  LibraryView.swift
//  YomiPlay
//
//  保存済みドキュメント：分组一覧（UI/UX 設計に基づく）
//

import SwiftUI

struct LibraryView: View {
    @Bindable var viewModel: HomeViewModel
    @Binding var navigationPath: NavigationPath
    @FocusState private var isSearchFocused: Bool
    @State private var showNewFolderAlert = false
    @State private var newFolderName = ""
    
    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            
            if viewModel.hasNoSavedDocuments {
                emptyStateView
            } else if viewModel.filteredDocuments.isEmpty {
                noResultsView
            } else {
                groupListView
            }
        }
        .background(Color(.systemGroupedBackground))
        .contentShape(Rectangle())
        .onTapGesture { isSearchFocused = false }
        .navigationTitle("saved_records")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    newFolderName = ""
                    showNewFolderAlert = true
                } label: {
                    Label("new_folder", systemImage: "folder.badge.plus")
                }
            }
        }
        .onAppear { viewModel.loadSavedDocuments() }
        .alert("new_folder", isPresented: $showNewFolderAlert) {
            TextField("folder_name", text: $newFolderName)
            Button("cancel", role: .cancel) {}
            Button("save") {
                viewModel.createFolder(name: newFolderName)
            }
            .disabled(newFolderName.trimmingCharacters(in: .whitespaces).isEmpty)
        } message: {
            Text("new_folder_message")
        }
        .alert("delete_folder", isPresented: $viewModel.showDeleteFolderConfirmation) {
            Button("cancel", role: .cancel) {
                viewModel.folderToDelete = nil
            }
            Button("delete", role: .destructive) {
                if let folder = viewModel.folderToDelete {
                    viewModel.deleteFolder(folder)
                }
            }
        } message: {
            if let folder = viewModel.folderToDelete {
                let count = viewModel.documentCount(inFolderId: folder.id)
                Text(deleteFolderMessage(count: count, folderName: folder.name))
            }
        }
    }
    
    private var searchBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                // 搜索输入框
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                    TextField("search_placeholder", text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .focused($isSearchFocused)
                        .submitLabel(.search)
                    if !viewModel.searchText.isEmpty {
                        Button {
                            viewModel.searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.body)
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isSearchFocused ? Color.green.opacity(0.5) : Color.clear, lineWidth: 1.5)
                )
                // 排序：显示当前模式 + 下拉
                Menu {
                    ForEach(DocumentSortOrder.allCases, id: \.self) { order in
                        Button {
                            viewModel.sortOrder = order
                        } label: {
                            HStack {
                                Text(order.displayName)
                                if viewModel.sortOrder == order { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down.circle.fill")
                            .font(.body)
                            .foregroundStyle(.green)
                        Text(viewModel.sortOrder.displayName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            // 有搜索词时显示结果数量
            if !viewModel.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                HStack {
                    Text(searchResultSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        viewModel.searchText = ""
                        isSearchFocused = false
                    } label: {
                        Text("clear_search")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
    }
    
    private var searchResultSummary: String {
        let count = viewModel.filteredDocuments.count
        let template = String(localized: "search_result_count")
        return String(format: template, "\(count)")
    }
    
    private var groupListView: some View {
        List {
            Section {
                // 未分组（默认，不可删除/重命名）
                groupRow(
                    id: nil,
                    name: String(localized: "uncategorized"),
                    count: viewModel.documents(inFolderId: nil).count,
                    isDefault: true
                )
            } header: {
                Text("default_group")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if !viewModel.folders.isEmpty {
                Section {
                    ForEach(viewModel.folders) { folder in
                        groupRow(
                            id: folder.id,
                            name: folder.name,
                            count: viewModel.documents(inFolderId: folder.id).count,
                            isDefault: false,
                            onRename: { viewModel.startRenamingFolder(folder) },
                            onDelete: { viewModel.requestDeleteFolder(folder) }
                        )
                    }
                } header: {
                    Text("my_groups")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // 底部「新建分组」入口，始终可见
            Section {
                Button {
                    newFolderName = ""
                    showNewFolderAlert = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                        Text("new_folder")
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundStyle(.green)
                    }
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.immediately)
    }
    
    private func groupRow(
        id: UUID?,
        name: String,
        count: Int,
        isDefault: Bool,
        onRename: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) -> some View {
        Button {
            HapticManager.shared.impact(style: .light)
            navigationPath.append(AppDestination.folder(folderId: id))
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "folder.fill")
                    .font(.title2)
                    .foregroundStyle(isDefault ? Color(.systemGray) : .yellow)
                    .frame(width: 32, alignment: .center)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(count) \("items")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color(.secondarySystemGroupedBackground))
        .contextMenu {
            if let onRename = onRename {
                Button {
                    onRename()
                } label: {
                    Label("rename", systemImage: "pencil")
                }
            }
            if let onDelete = onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("delete_folder", systemImage: "trash")
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if let onRename = onRename {
                Button {
                    onRename()
                } label: {
                    Label("rename", systemImage: "pencil")
                }
                .tint(.blue)
            }
            if let onDelete = onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("delete_folder", systemImage: "trash")
                }
            }
        }
    }
    
    private func deleteFolderMessage(count: Int, folderName: String) -> String {
        let template = String(localized: "delete_folder_confirmation_message")
        return String(format: template, "\(count)", folderName)
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
}

/// フォルダ内の記録一覧＋「他のフォルダへ移動」
struct FolderContentView: View {
    @Bindable var viewModel: HomeViewModel
    let folderId: UUID?
    @Binding var navigationPath: NavigationPath
    @State private var documentToMove: TranscriptDocument?
    
    private var folderName: String {
        viewModel.folderDisplayName(for: folderId)
    }
    
    private var documents: [TranscriptDocument] {
        viewModel.documents(inFolderId: folderId)
    }
    
    var body: some View {
        Group {
            if documents.isEmpty {
                emptyFolderView
            } else {
                List {
                    ForEach(documents) { doc in
                        documentRow(doc)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(folderName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $documentToMove) { doc in
            MoveToFolderSheet(
                viewModel: viewModel,
                document: doc,
                currentFolderId: folderId,
                onDismiss: {
                    documentToMove = nil
                }
            )
        }
    }
    
    private func documentRow(_ doc: TranscriptDocument) -> some View {
        Button {
            HapticManager.shared.impact(style: .light)
            let allDocs = viewModel.filteredDocuments
            if let index = allDocs.firstIndex(of: doc) {
                navigationPath.append(AppDestination.player(documents: allDocs, currentIndex: index))
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: doc.source.videoPlaybackURL != nil ? "play.rectangle.fill" : "waveform")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 28)
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
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(RecordRowButtonStyle())
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
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
            Button {
                documentToMove = doc
            } label: {
                Label("move_to_folder", systemImage: "folder")
            }
            .tint(.green)
        }
    }
    
    private var emptyFolderView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "folder")
                .font(.system(size: 60))
                .foregroundStyle(.secondary.opacity(0.5))
            Text("folder_empty")
                .font(.subheadline)
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

/// 記録を別フォルダへ移動するシート
struct MoveToFolderSheet: View {
    @Bindable var viewModel: HomeViewModel
    let document: TranscriptDocument
    let currentFolderId: UUID?
    let onDismiss: () -> Void
    
    var body: some View {
        NavigationStack {
            List {
                Button {
                    viewModel.moveDocument(document, toFolderId: nil)
                    onDismiss()
                } label: {
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.gray)
                        Text("uncategorized")
                        if currentFolderId == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.green)
                        }
                    }
                }
                ForEach(viewModel.folders) { folder in
                    Button {
                        viewModel.moveDocument(document, toFolderId: folder.id)
                        onDismiss()
                    } label: {
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(.yellow)
                            Text(folder.name)
                            if currentFolderId == folder.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
            }
            .navigationTitle("move_to_folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") { onDismiss() }
                }
            }
        }
    }
}

/// 記録行専用のボタンラベルスタイル
struct RecordRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color(.systemFill) : Color.clear)
            .contentShape(Rectangle())
    }
}
