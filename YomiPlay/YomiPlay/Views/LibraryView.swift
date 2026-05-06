//
//  LibraryView.swift
//  YomiPlay
//
//  保存済みドキュメント：分组一覧（UI/UX 設計に基づく）
//

import SwiftUI

// MARK: - 排序菜单（自动 / 自定义分组）

private enum LibrarySortMenuContent {
    @ViewBuilder
    static func menu(viewModel: HomeViewModel) -> some View {
        Section {
            sortButton(viewModel, order: .titleAscending)
            sortButton(viewModel, order: .dateNewestFirst)
            sortButton(viewModel, order: .dateOldestFirst)
            sortButton(viewModel, order: .titleDescending)
        } header: {
            Text(LocalizedStringResource("library_sort_section_auto"))
        }
        Section {
            sortButton(viewModel, order: .manual)
        } header: {
            Text(LocalizedStringResource("library_sort_section_custom"))
        }
    }
    
    private static func sortButton(_ viewModel: HomeViewModel, order: DocumentSortOrder) -> some View {
        Button {
            viewModel.sortOrder = order
        } label: {
            HStack {
                Text(order.displayName)
                Spacer()
                if viewModel.sortOrder == order {
                    Image(systemName: "checkmark")
                }
            }
        }
    }
}

/// 库首页：排序 + 分组拖动排序，收起到「更多」菜单
private struct LibraryHomeOverflowMenu: View {
    @Bindable var viewModel: HomeViewModel
    @Binding var folderListEditMode: EditMode
    
    var body: some View {
        Menu {
            LibrarySortMenuContent.menu(viewModel: viewModel)
            if !viewModel.folders.isEmpty {
                Divider()
                Button {
                    folderListEditMode = folderListEditMode == .active ? .inactive : .active
                } label: {
                    Label(
                        folderListEditMode == .active ? "library_sort_reorder_done" : "library_folder_reorder_edit",
                        systemImage: "arrow.up.arrow.down"
                    )
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel(String(localized: "library_toolbar_more"))
    }
}

/// 分组内页：排序 + 记录编辑顺序 + 多选，收起到「更多」菜单
private struct FolderContentOverflowMenu: View {
    @Bindable var viewModel: HomeViewModel
    @Binding var manualReorderEditMode: EditMode
    let canManualReorder: Bool
    let onStartBatch: () -> Void
    
    var body: some View {
        Menu {
            LibrarySortMenuContent.menu(viewModel: viewModel)
            if canManualReorder {
                Divider()
                Button {
                    manualReorderEditMode = manualReorderEditMode == .active ? .inactive : .active
                } label: {
                    Label(
                        manualReorderEditMode == .active ? "library_sort_reorder_done" : "library_sort_reorder_edit",
                        systemImage: "arrow.up.arrow.down"
                    )
                }
            }
            Divider()
            Button(action: onStartBatch) {
                Label("library_batch_select", systemImage: "checkmark.circle")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel(String(localized: "library_toolbar_more"))
    }
}

struct LibraryView: View {
    @Bindable var viewModel: HomeViewModel
    @Binding var navigationPath: NavigationPath
    @State private var showNewFolderAlert = false
    @State private var newFolderName = ""
    @State private var showLibrarySearchSheet = false
    /// 库首页「我的分组」拖动排序
    @State private var folderListEditMode: EditMode = .inactive
    
    var body: some View {
        VStack(spacing: 0) {
            headerSection
            if viewModel.hasNoSavedDocuments {
                emptyStateView
            } else {
                groupListView
            }
        }
        .background(Color(.systemBackground))
        .contentShape(Rectangle())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !viewModel.hasNoSavedDocuments {
                librarySearchBarButton
            }
        }
        .sheet(isPresented: $showLibrarySearchSheet) {
            LibrarySearchSheet(viewModel: viewModel, navigationPath: $navigationPath, isPresented: $showLibrarySearchSheet)
        }
        .navigationTitle("saved_records")
        .toolbar {
            if !viewModel.hasNoSavedDocuments {
                if folderListEditMode == .active {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("library_sort_reorder_done") {
                            folderListEditMode = .inactive
                        }
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        LibraryHomeOverflowMenu(viewModel: viewModel, folderListEditMode: $folderListEditMode)
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
        .onChange(of: viewModel.folders.count) { _, count in
            if count == 0 { folderListEditMode = .inactive }
        }
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
        VStack(spacing: 14) {
            // 与导入页头部同尺寸的图标容器
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.accentColor.opacity(0.08))
                    .frame(width: 96, height: 56)
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.secondary)
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }

            VStack(spacing: 6) {
                Text("library_header_title")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("library_subtitle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)   // 与导入页 headerSection 对齐
        .padding(.bottom, 8)
    }

    /// 底部搜索入口（宽度随文案，类似 iPhone 主屏搜索按钮）
    private var librarySearchBarButton: some View {
        HStack {
            Spacer(minLength: 0)
            Button {
                HapticManager.shared.impact(style: .light)
                showLibrarySearchSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text("search_placeholder")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 9)
                .padding(.horizontal, 14)
                .background(.ultraThinMaterial)
                .clipShape(Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color(.separator).opacity(0.35), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }
    
    private var groupListView: some View {
        List {
            Section {
                Color.clear
                    .frame(height: 8)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .accessibilityHidden(true)
            }
            Section {
                groupCard(
                    id: nil,
                    name: String(localized: LocalizedStringResource("uncategorized", locale: AppLocale.current)),
                    count: viewModel.documents(inFolderId: nil).count,
                    isDefault: true,
                    blockNavigation: false,
                    showDisclosure: true,
                    onExport: viewModel.documents(inFolderId: nil).isEmpty ? nil : { viewModel.exportFolderAsZip(folderId: nil) }
                )
                .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            if !viewModel.folders.isEmpty {
                Section {
                    ForEach(viewModel.folders) { folder in
                        groupCard(
                            id: folder.id,
                            name: folder.name,
                            count: viewModel.documents(inFolderId: folder.id).count,
                            isDefault: false,
                            blockNavigation: folderListEditMode == .active,
                            showDisclosure: folderListEditMode != .active,
                            onRename: { viewModel.startRenamingFolder(folder) },
                            onDelete: { viewModel.requestDeleteFolder(folder) },
                            onExport: viewModel.documents(inFolderId: folder.id).isEmpty ? nil : { viewModel.exportFolderAsZip(folderId: folder.id) }
                        )
                        .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    .onMove { from, to in
                        viewModel.reorderFolders(from: from, to: to)
                    }
                } header: {
                    Text("my_groups")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textCase(nil)
                        .padding(.bottom, 2)
                } footer: {
                    if folderListEditMode == .active {
                        Text("library_folder_reorder_footer")
                            .font(.caption2)
                    }
                }
            }
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(.systemBackground))
        .environment(\.editMode, $folderListEditMode)
        .scrollDismissesKeyboard(.immediately)
    }
    
    private func groupCard(
        id: UUID?,
        name: String,
        count: Int,
        isDefault: Bool,
        blockNavigation: Bool = false,
        showDisclosure: Bool = true,
        onRename: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        onExport: (() -> Void)? = nil
    ) -> some View {
        Button {
            guard !blockNavigation else { return }
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
                if showDisclosure {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
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
            if !blockNavigation, let onExport = onExport {
                Button {
                    onExport()
                } label: {
                    Label("export_folder_as_zip", systemImage: "square.and.arrow.up")
                }
            }
            if !blockNavigation, let onRename = onRename {
                Button {
                    onRename()
                } label: {
                    Label("rename", systemImage: "pencil")
                }
            }
            if !blockNavigation, let onDelete = onDelete {
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
}

// MARK: - 库内搜索 Sheet（双 Section：分组 / 记录）

private struct LibrarySearchSheet: View {
    @Bindable var viewModel: HomeViewModel
    @Binding var navigationPath: NavigationPath
    @Binding var isPresented: Bool
    @State private var query = ""
    @FocusState private var searchFieldFocused: Bool
    
    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }
    
    private var matchingFolders: [LibrarySearchFolderMatch] {
        viewModel.librarySearchMatchingFolders(query: query)
    }
    
    private var matchingDocuments: [TranscriptDocument] {
        viewModel.librarySearchMatchingDocuments(query: query)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                    TextField("search_placeholder", text: $query)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($searchFieldFocused)
                        .submitLabel(.search)
                    if !trimmedQuery.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                
                List {
                    if trimmedQuery.isEmpty {
                        Section {
                            HStack(spacing: 10) {
                                Image(systemName: "text.magnifyingglass")
                                    .foregroundStyle(.tertiary)
                                Text("library_search_hint")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 8)
                            .listRowBackground(Color.clear)
                        }
                    } else if matchingFolders.isEmpty && matchingDocuments.isEmpty {
                        Section {
                            HStack {
                                Spacer()
                                VStack(spacing: 10) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.largeTitle)
                                        .foregroundStyle(.tertiary)
                                    Text("no_matching_records")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 28)
                                Spacer()
                            }
                            .listRowBackground(Color.clear)
                        }
                    } else {
                        if !matchingFolders.isEmpty {
                            Section {
                                ForEach(matchingFolders) { match in
                                    Button {
                                        openFolder(match.folderId)
                                    } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: "folder.fill")
                                                .foregroundStyle(match.folderId == nil ? Color(.systemGray) : .yellow)
                                            Text(match.name)
                                                .foregroundStyle(.primary)
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                }
                            } header: {
                                Text("library_search_section_groups")
                            }
                        }
                        if !matchingDocuments.isEmpty {
                            Section {
                                ForEach(matchingDocuments) { doc in
                                    Button {
                                        openPlayer(for: doc)
                                    } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: doc.source.videoPlaybackURL != nil ? "play.rectangle.fill" : "waveform")
                                                .foregroundStyle(.secondary)
                                                .frame(width: 28)
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(doc.source.title)
                                                    .font(.headline)
                                                    .foregroundStyle(.primary)
                                                    .lineLimit(2)
                                                Text(viewModel.folderDisplayName(for: doc.folderId))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer(minLength: 0)
                                            Image(systemName: "chevron.right")
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                }
                            } header: {
                                Text("library_search_section_records")
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("search_placeholder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") {
                        query = ""
                        isPresented = false
                    }
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    searchFieldFocused = true
                }
            }
        }
    }
    
    private func openFolder(_ folderId: UUID?) {
        isPresented = false
        let id = folderId
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            navigationPath.append(AppDestination.folder(folderId: id))
        }
    }
    
    private func openPlayer(for doc: TranscriptDocument) {
        isPresented = false
        let folderDocs = viewModel.documents(inFolderId: doc.folderId)
        let index = folderDocs.firstIndex(where: { $0.id == doc.id }) ?? 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            navigationPath.append(AppDestination.player(documents: folderDocs, currentIndex: index))
        }
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
    @State private var searchText: String = ""
    @State private var isBatchMode = false
    @State private var selectedDocumentIds: Set<UUID> = []
    @State private var showBatchMoveSheet = false
    @State private var showBatchDeleteConfirmation = false
    /// 手动排序时：编辑模式下显示拖动控件
    @State private var manualReorderEditMode: EditMode = .inactive
    
    private var folderName: String {
        viewModel.folderDisplayName(for: folderId)
    }
    
    private var documents: [TranscriptDocument] {
        viewModel.documents(inFolderId: folderId)
    }

    private var filteredDocuments: [TranscriptDocument] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return documents }
        return documents.filter { doc in
            doc.source.title.localizedCaseInsensitiveContains(keyword)
        }
    }
    
    private var canManualReorder: Bool {
        viewModel.sortOrder == .manual && !isBatchMode && searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selectedDocumentsForBatch: [TranscriptDocument] {
        documents.filter { selectedDocumentIds.contains($0.id) }
    }

    private var allFilteredSelected: Bool {
        !filteredDocuments.isEmpty && filteredDocuments.allSatisfy { selectedDocumentIds.contains($0.id) }
    }

    private var batchNavigationTitle: String {
        if isBatchMode, !selectedDocumentIds.isEmpty {
            let fmt = String(localized: LocalizedStringResource("library_batch_selected_count_format", locale: AppLocale.current))
            return String(format: fmt, selectedDocumentIds.count)
        }
        return folderName
    }
    
    var body: some View {
        Group {
            if documents.isEmpty {
                emptyFolderView
            } else {
                List {
                    // 分组内搜索框
                    Section {
                        HStack(spacing: 10) {
                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.body)
                                    .foregroundStyle(.tertiary)
                                TextField("search_placeholder", text: $searchText)
                                    .textFieldStyle(.plain)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(.secondarySystemBackground))
                            )
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    }
                    
                    Section {
                        if canManualReorder {
                            ForEach(filteredDocuments) { doc in
                                documentRow(doc)
                            }
                            .onMove { from, to in
                                viewModel.reorderDocumentsInFolder(folderId: folderId, from: from, to: to)
                            }
                        } else {
                            ForEach(filteredDocuments) { doc in
                                documentRow(doc)
                            }
                        }
                        
                        // 分组底部导入按钮：跳转到导入页，导入到当前分组
                        if !isBatchMode {
                            Button {
                                // 先关闭当前分组页面（返回到分组列表）
                                if !navigationPath.isEmpty {
                                    navigationPath.removeLast()
                                }
                                // 记录目标分组 ID，并请求切换到导入 Tab
                                viewModel.currentImportFolderId = folderId
                                viewModel.requestSwitchToImportTab = true
                            } label: {
                                HStack {
                                    Spacer()
                                    Image(systemName: "square.and.arrow.down")
                                    Text("import")
                                    Spacer()
                                }
                            }
                        }
                    } footer: {
                        if canManualReorder {
                            Text("library_sort_manual_footer")
                                .font(.caption2)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .environment(\.editMode, $manualReorderEditMode)
            }
        }
        .navigationTitle(batchNavigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isBatchMode {
                ToolbarItem(placement: .cancellationAction) {
                    Button("library_batch_done") {
                        isBatchMode = false
                        selectedDocumentIds = []
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(allFilteredSelected ? "library_batch_deselect_all" : "library_batch_select_all") {
                        if allFilteredSelected {
                            let ids = Set(filteredDocuments.map(\.id))
                            selectedDocumentIds.subtract(ids)
                        } else {
                            selectedDocumentIds.formUnion(filteredDocuments.map(\.id))
                        }
                    }
                    .disabled(filteredDocuments.isEmpty)
                }
            } else if manualReorderEditMode == .active {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("library_sort_reorder_done") {
                        manualReorderEditMode = .inactive
                    }
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    FolderContentOverflowMenu(
                        viewModel: viewModel,
                        manualReorderEditMode: $manualReorderEditMode,
                        canManualReorder: canManualReorder,
                        onStartBatch: {
                            isBatchMode = true
                            selectedDocumentIds = []
                            manualReorderEditMode = .inactive
                        }
                    )
                }
            }
        }
        .onChange(of: viewModel.sortOrder) { _, new in
            if new != .manual {
                manualReorderEditMode = .inactive
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
        .sheet(isPresented: $showBatchMoveSheet) {
            BatchMoveToFolderSheet(
                viewModel: viewModel,
                documents: selectedDocumentsForBatch,
                currentFolderId: folderId,
                onCancel: { showBatchMoveSheet = false },
                onMoved: {
                    showBatchMoveSheet = false
                    isBatchMode = false
                    selectedDocumentIds = []
                }
            )
        }
        .alert("library_batch_delete_alert_title", isPresented: $showBatchDeleteConfirmation) {
            Button("cancel", role: .cancel) {}
            Button("delete", role: .destructive) {
                viewModel.deleteDocuments(selectedDocumentsForBatch)
                isBatchMode = false
                selectedDocumentIds = []
            }
        } message: {
            let fmt = String(localized: LocalizedStringResource("library_batch_delete_message", locale: AppLocale.current))
            Text(String(format: fmt, selectedDocumentIds.count))
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isBatchMode, !documents.isEmpty {
                VStack(spacing: 0) {
                    Divider()
                    HStack(spacing: 20) {
                        Button {
                            showBatchMoveSheet = true
                        } label: {
                            Label("library_batch_move", systemImage: "folder")
                                .font(.subheadline.weight(.medium))
                        }
                        .disabled(selectedDocumentIds.isEmpty)
                        Spacer()
                        Button(role: .destructive) {
                            showBatchDeleteConfirmation = true
                        } label: {
                            Label("library_batch_delete", systemImage: "trash")
                                .font(.subheadline.weight(.medium))
                        }
                        .disabled(selectedDocumentIds.isEmpty)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.bar)
                }
            }
        }
    }
    
    private func documentRow(_ doc: TranscriptDocument) -> some View {
        let blockReorderTap = manualReorderEditMode == .active && viewModel.sortOrder == .manual
        return Button {
            if isBatchMode {
                HapticManager.shared.impact(style: .light)
                if selectedDocumentIds.contains(doc.id) {
                    selectedDocumentIds.remove(doc.id)
                } else {
                    selectedDocumentIds.insert(doc.id)
                }
                return
            }
            guard allowRowTap, !blockReorderTap else { return }
            HapticManager.shared.impact(style: .light)
            // 分组内进入播放：播放列表仅含本分组记录（与当前列表顺序一致），便于顺序播放时停留在分组内
            let folderDocs = documents
            if let index = folderDocs.firstIndex(where: { $0.id == doc.id }) {
                navigationPath.append(AppDestination.player(documents: folderDocs, currentIndex: index))
            }
        } label: {
            HStack(spacing: 12) {
                if isBatchMode {
                    Image(systemName: selectedDocumentIds.contains(doc.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(selectedDocumentIds.contains(doc.id) ? Color.accentColor : .secondary)
                        .frame(width: 28)
                }
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
                if !isBatchMode {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(RecordRowButtonStyle())
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !isBatchMode && !blockReorderTap {
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

/// 複数記録を別フォルダへ一括移動
struct BatchMoveToFolderSheet: View {
    @Bindable var viewModel: HomeViewModel
    let documents: [TranscriptDocument]
    let currentFolderId: UUID?
    let onCancel: () -> Void
    let onMoved: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if documents.isEmpty {
                    ContentUnavailableView(
                        "library_batch_move_empty",
                        systemImage: "folder",
                        description: Text("library_batch_move_empty_hint")
                    )
                } else {
                    List {
                        Button {
                            viewModel.moveDocuments(documents, toFolderId: nil)
                            onMoved()
                        } label: {
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(.gray)
                                Text(String(localized: LocalizedStringResource("uncategorized", locale: AppLocale.current)))
                                if currentFolderId == nil {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                        ForEach(viewModel.folders) { folder in
                            Button {
                                viewModel.moveDocuments(documents, toFolderId: folder.id)
                                onMoved()
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
                }
            }
            .navigationTitle("move_to_folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") { onCancel() }
                }
            }
        }
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
                        Text(String(localized: LocalizedStringResource("uncategorized", locale: AppLocale.current)))
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
