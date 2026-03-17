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
            headerSection
            searchSection
            if viewModel.hasNoSavedDocuments {
                emptyStateView
            } else if viewModel.filteredDocuments.isEmpty {
                noResultsView
            } else {
                groupListView
            }
        }
        .background(Color(.systemBackground))
        .contentShape(Rectangle())
        .onTapGesture { isSearchFocused = false }
        .navigationTitle("saved_records")
        .toolbar {
            if !viewModel.hasNoSavedDocuments {
                ToolbarItem(placement: .topBarTrailing) {
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
                        Label("sort_label", systemImage: "arrow.up.arrow.down.circle")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
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
    
    // MARK: - 头部：与导入页风格统一（标题 + 副标题）
    private var headerSection: some View {
        VStack(spacing: 6) {
            Image(systemName: "clock.fill")
                .font(.system(size: 44))
                .foregroundStyle(.linearGradient(colors: [.green, .green.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .symbolRenderingMode(.hierarchical)
            Text("library_header_title")
                .font(.title2)
                .fontWeight(.bold)
            Text("library_header_subtitle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    // MARK: - 搜索：卡片式，与导入页区块风格一致
    private var searchSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                TextField("search_placeholder", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .focused($isSearchFocused)
                    .submitLabel(.search)
                if !viewModel.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button {
                        viewModel.searchText = ""
                        isSearchFocused = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSearchFocused ? Color.green.opacity(0.4) : Color.clear, lineWidth: 1.5)
            )
            if !viewModel.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                HStack(spacing: 8) {
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
                            .fontWeight(.medium)
                            .foregroundStyle(.green)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }
    
    private var searchResultSummary: String {
        let count = viewModel.filteredDocuments.count
        let template = String(localized: "search_result_count")
        return String(format: template, "\(count)")
    }
    
    private var groupListView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                sectionLabel("default_group")
                groupCard(
                    id: nil,
                    name: String(localized: "uncategorized"),
                    count: viewModel.documents(inFolderId: nil).count,
                    isDefault: true,
                    onExport: viewModel.documents(inFolderId: nil).isEmpty ? nil : { viewModel.exportFolderAsZip(folderId: nil) }
                )
                if !viewModel.folders.isEmpty {
                    sectionLabel("my_groups")
                    ForEach(viewModel.folders) { folder in
                        groupCard(
                            id: folder.id,
                            name: folder.name,
                            count: viewModel.documents(inFolderId: folder.id).count,
                            isDefault: false,
                            onRename: { viewModel.startRenamingFolder(folder) },
                            onDelete: { viewModel.requestDeleteFolder(folder) },
                            onExport: viewModel.documents(inFolderId: folder.id).isEmpty ? nil : { viewModel.exportFolderAsZip(folderId: folder.id) }
                        )
                    }
                }
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                Spacer(minLength: 24)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .scrollDismissesKeyboard(.immediately)
    }
    
    private func sectionLabel(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
    }
    
    private func groupCard(
        id: UUID?,
        name: String,
        count: Int,
        isDefault: Bool,
        onRename: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        onExport: (() -> Void)? = nil
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
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contextMenu {
            if let onExport = onExport {
                Button {
                    onExport()
                } label: {
                    Label("export_folder_as_zip", systemImage: "square.and.arrow.up")
                }
            }
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
    }
    
    private func deleteFolderMessage(count: Int, folderName: String) -> String {
        let template = String(localized: "delete_folder_confirmation_message")
        return String(format: template, "\(count)", folderName)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "doc.plaintext")
                .font(.system(size: 64))
                .foregroundStyle(.linearGradient(colors: [.green.opacity(0.4), .green.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .symbolRenderingMode(.hierarchical)
            VStack(spacing: 10) {
                Text("no_records_yet")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("import_audio_video_to_start")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding(.horizontal, 20)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 20)
    }
    
    private var noResultsView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.6))
            Text("no_matching_records")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 20)
    }
}

/// フォルダ内の記録一覧＋「他のフォルダへ移動」
struct FolderContentView: View {
    @Bindable var viewModel: HomeViewModel
    let folderId: UUID?
    @Binding var navigationPath: NavigationPath
    @State private var documentToMove: TranscriptDocument?
    /// 进入分组后短时内不响应行点击，避免列表未完全呈现时的二次点击误进播放页
    @State private var allowRowTap: Bool = false
    
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
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
                    Label("sort_label", systemImage: "arrow.up.arrow.down.circle")
                }
            }
        }
        .onAppear {
            allowRowTap = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                allowRowTap = true
            }
        }
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
            guard allowRowTap else { return }
            HapticManager.shared.impact(style: .light)
            // 分组内进入播放：播放列表仅含本分组记录（与当前列表顺序一致），便于顺序播放时停留在分组内
            let folderDocs = documents
            if let index = folderDocs.firstIndex(where: { $0.id == doc.id }) {
                navigationPath.append(AppDestination.player(documents: folderDocs, currentIndex: index))
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
