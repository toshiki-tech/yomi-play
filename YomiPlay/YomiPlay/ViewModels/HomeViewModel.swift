//
//  HomeViewModel.swift
//  YomiPlay
//
//  ホーム画面のViewModel
//

import Foundation
import SwiftUI
import PhotosUI
import AVFoundation

/// 保存済み記録一覧の並び順
enum DocumentSortOrder: String, CaseIterable, Hashable {
    case dateNewestFirst
    case dateOldestFirst
    case titleAscending
    case titleDescending
    case segmentCountDescending
    
    var displayName: String {
        switch self {
        case .dateNewestFirst: return String(localized: "date_newest_first")
        case .dateOldestFirst: return String(localized: "date_oldest_first")
        case .titleAscending: return String(localized: "name_a_z")
        case .titleDescending: return String(localized: "name_z_a")
        case .segmentCountDescending: return String(localized: "segments_most_first")
        }
    }
    
    var predicate: (TranscriptDocument, TranscriptDocument) -> Bool {
        switch self {
        case .dateNewestFirst:
            return { $0.createdAt > $1.createdAt }
        case .dateOldestFirst:
            return { $0.createdAt < $1.createdAt }
        case .titleAscending:
            return { $0.source.title.localizedCompare($1.source.title) == .orderedAscending }
        case .titleDescending:
            return { $0.source.title.localizedCompare($1.source.title) == .orderedDescending }
        case .segmentCountDescending:
            return { $0.segments.count > $1.segments.count }
        }
    }
}

/// 記録一覧のグループ（フォルダ or 未グループ）
struct GroupedLibraryItem: Identifiable {
    let id: String
    let folder: TranscriptFolder?
    let documents: [TranscriptDocument]
    init(folder: TranscriptFolder?, documents: [TranscriptDocument]) {
        self.folder = folder
        self.documents = documents
        self.id = folder?.id.uuidString ?? "uncategorized"
    }
}

@Observable
final class HomeViewModel {
    
    // UI 状態
    var urlText: String = ""
    var isFileImporterPresented: Bool = false
    var errorMessage: String?
    var showError: Bool = false
    var isLoadingVideo: Bool = false
    
    /// fileImporter の用途を区別するフラグ
    enum FileImportMode {
        case audioVideo
        case srt
        case yomi
        case zip
    }
    var fileImportMode: FileImportMode = .audioVideo
    
    /// ZIP インポート処理中
    var isImportingZip: Bool = false
    var zipImportProgressMessage: String = ""
    
    // 検索・フィルタリング
    var searchText: String = ""
    /// 一覧の並び順
    var sortOrder: DocumentSortOrder = .dateNewestFirst
    private var allSavedDocuments: [TranscriptDocument] = []
    private var allFolders: [TranscriptFolder] = []
    /// フォルダ一覧（UI 用の読み取り専用）
    var folders: [TranscriptFolder] { allFolders }
    
    // ナビゲーション
    var selectedAudioSource: AudioSource?
    var navigateToProcessing: Bool = false
    var navigateToPlayerDocument: TranscriptDocument?
    var navigateToPlayer: Bool = false
    
    // SRT 附带选择
    var pendingAudioSource: AudioSource?
    var showSRTOption: Bool = false
    
    // 重命名
    var documentToRename: TranscriptDocument?
    var newTitle: String = ""
    var showRenameAlert: Bool = false
    
    // フォルダ重命名
    var folderToRename: TranscriptFolder?
    var newFolderName: String = ""
    var showFolderRenameAlert: Bool = false
    
    // フォルダ削除確認（削除対象を保持）
    var folderToDelete: TranscriptFolder?
    var showDeleteFolderConfirmation: Bool = false
    
    init() {
        loadSavedDocuments()
    }
    
    /// 保存済みドキュメントとフォルダを読み込む
    func loadSavedDocuments() {
        allSavedDocuments = DocumentStore.shared.loadAll()
        allFolders = DocumentStore.shared.loadAllFolders()
    }
    
    /// フォルダ＋未グループでグループ化した一覧（検索・並び順適用済み）
    var groupedLibrary: [GroupedLibraryItem] {
        let docs = filteredDocuments
        var result: [GroupedLibraryItem] = []
        for f in allFolders {
            let group = docs.filter { $0.folderId == f.id }
            if !group.isEmpty { result.append(GroupedLibraryItem(folder: f, documents: group)) }
        }
        let uncategorized = docs.filter { $0.folderId == nil }
        if !uncategorized.isEmpty { result.append(GroupedLibraryItem(folder: nil, documents: uncategorized)) }
        return result
    }
    
    /// 検索フィルタリング＋並び順適用済みのドキュメント一覧
    var filteredDocuments: [TranscriptDocument] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let list: [TranscriptDocument]
        if query.isEmpty {
            list = allSavedDocuments
        } else {
            list = allSavedDocuments.filter { doc in
                doc.source.title.localizedCaseInsensitiveContains(query)
                    || doc.segments.contains { $0.originalText.localizedCaseInsensitiveContains(query) }
            }
        }
        return list.sorted(by: sortOrder.predicate)
    }
    
    /// 保存済みが 0 件か（空状態ガイド表示用）
    var hasNoSavedDocuments: Bool { allSavedDocuments.isEmpty }
    
    /// 削除確認用にフォルダを指定し、確認ダイアログを表示する
    func requestDeleteFolder(_ folder: TranscriptFolder) {
        folderToDelete = folder
        showDeleteFolderConfirmation = true
    }
    
    /// フォルダを削除する（配下のドキュメントは未グループに移す）
    func deleteFolder(_ folder: TranscriptFolder) {
        var updated = allSavedDocuments
        for i in updated.indices where updated[i].folderId == folder.id {
            updated[i].folderId = nil
            try? DocumentStore.shared.save(updated[i])
        }
        try? DocumentStore.shared.deleteFolder(id: folder.id)
        folderToDelete = nil
        showDeleteFolderConfirmation = false
        loadSavedDocuments()
    }
    
    /// 指定フォルダ内のドキュメント数
    func documentCount(inFolderId folderId: UUID?) -> Int {
        allSavedDocuments.filter { $0.folderId == folderId }.count
    }
    
    /// 指定フォルダ内のドキュメント一覧（folderId == nil で未分组）
    func documents(inFolderId folderId: UUID?) -> [TranscriptDocument] {
        filteredDocuments.filter { $0.folderId == folderId }
    }
    
    /// フォルダ ID からフォルダを取得
    func folder(byId id: UUID) -> TranscriptFolder? {
        allFolders.first { $0.id == id }
    }
    
    /// フォルダ表示名（nil = 未分组）
    func folderDisplayName(for folderId: UUID?) -> String {
        guard let id = folderId, let f = folder(byId: id) else { return String(localized: "uncategorized") }
        return f.name
    }
    
    /// 新規フォルダを作成する
    func createFolder(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let folder = TranscriptFolder(name: trimmed)
        do {
            try DocumentStore.shared.addFolder(folder)
            loadSavedDocuments()
        } catch {
            showErrorMessage(error.localizedDescription)
        }
    }
    
    /// ドキュメントを指定フォルダに移動する（nil = 未分组）
    func moveDocument(_ document: TranscriptDocument, toFolderId folderId: UUID?) {
        guard var updated = allSavedDocuments.first(where: { $0.id == document.id }) else { return }
        updated.folderId = folderId
        do {
            try DocumentStore.shared.save(updated)
            loadSavedDocuments()
        } catch {
            showErrorMessage(error.localizedDescription)
        }
    }
    
    /// フォルダ名の変更を開始
    func startRenamingFolder(_ folder: TranscriptFolder) {
        folderToRename = folder
        newFolderName = folder.name
        showFolderRenameAlert = true
    }
    
    /// フォルダ名の変更を確定
    func confirmFolderRename() {
        guard var folder = folderToRename else { return }
        let name = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        folder.name = name
        do {
            try DocumentStore.shared.updateFolder(folder)
            loadSavedDocuments()
        } catch {
            showErrorMessage(error.localizedDescription)
        }
        folderToRename = nil
        showFolderRenameAlert = false
    }
    
    /// ドキュメントを削除する
    func deleteDocument(_ document: TranscriptDocument) {
        try? DocumentStore.shared.delete(id: document.id)
        allSavedDocuments.removeAll { $0.id == document.id }
    }
    
    /// 重命名の準備
    func startRenaming(_ document: TranscriptDocument) {
        documentToRename = document
        newTitle = document.source.title
        showRenameAlert = true
    }
    
    /// 重命名を確定する
    func confirmRename() {
        guard var doc = documentToRename else { return }
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        
        doc.source.title = title
        
        do {
            try DocumentStore.shared.save(doc)
            loadSavedDocuments() // 再読み込み
        } catch {
            showErrorMessage(String(localized: "rename_failed") + ": " + error.localizedDescription)
        }
        
        documentToRename = nil
        showRenameAlert = false
    }
    
    // MARK: - インポート処理（既存のロジックを保持）
    
    func handleFileSelected(result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else {
                showErrorMessage(String(localized: "no_permission_to_access_the_file"))
                return
            }
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let destinationURL = documentsURL.appendingPathComponent(url.lastPathComponent)
            do {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: url, to: destinationURL)
                url.stopAccessingSecurityScopedResource()
                if isVideoFile(url: destinationURL) {
                    extractAudioFromVideo(sourceURL: destinationURL, title: url.deletingPathExtension().lastPathComponent)
                } else {
                    promptSRTOption(for: AudioSource(
                        type: .local,
                        localURL: destinationURL,
                        relativeFilePath: destinationURL.lastPathComponent,
                        title: url.deletingPathExtension().lastPathComponent
                    ))
                }
            } catch {
                url.stopAccessingSecurityScopedResource()
                showErrorMessage(String(localized: "failed_to_copy_the_file"))
            }
        case .failure(let error):
            showErrorMessage(error.localizedDescription)
        }
    }
    
    func handlePhotoPickerItem(_ item: PhotosPickerItem) {
        isLoadingVideo = true
        Task {
            do {
                guard let videoData = try await item.loadTransferable(type: VideoTransferable.self) else {
                    await MainActor.run { isLoadingVideo = false; showErrorMessage(String(localized: "failed_to_load")) }
                    return
                }
                let videoTitle = String(localized: "camera_roll_video")
                await MainActor.run {
                    if isVideoFile(url: videoData.url) {
                        extractAudioFromVideo(sourceURL: videoData.url, title: videoTitle)
                    } else {
                        isLoadingVideo = false
                        promptSRTOption(for: AudioSource(
                            type: .local,
                            localURL: videoData.url,
                            relativeFilePath: videoData.url.lastPathComponent,
                            title: videoTitle
                        ))
                    }
                }
            } catch {
                await MainActor.run { isLoadingVideo = false; showErrorMessage(error.localizedDescription) }
            }
        }
    }
    
    func loadFromURL() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), url.scheme != nil else { return }
        promptSRTOption(for: AudioSource(type: .remote, remoteURL: url, title: url.deletingPathExtension().lastPathComponent))
    }
    
    // MARK: - SRT 附带导入
    
    /// 音视频选择完成后，弹出是否附带 SRT 的选项
    func promptSRTOption(for source: AudioSource) {
        pendingAudioSource = source
        showSRTOption = true
    }
    
    /// 用户选择跳过 SRT，直接进入处理流程
    func skipSRT() {
        guard let source = pendingAudioSource else { return }
        selectedAudioSource = source
        pendingAudioSource = nil
        showSRTOption = false
        navigateToProcessing = true
    }
    
    /// 用户选择了 SRT 文件，将其复制到 Documents 并附加到 AudioSource
    func attachSRT(url: URL) {
        guard var source = pendingAudioSource else { return }
        
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
        
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let srtFileName = "srt_\(UUID().uuidString).srt"
        let destinationURL = documentsURL.appendingPathComponent(srtFileName)
        
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: url, to: destinationURL)
            source.srtRelativeFilePath = srtFileName
            selectedAudioSource = source
            pendingAudioSource = nil
            showSRTOption = false
            navigateToProcessing = true
        } catch {
            showErrorMessage(String(localized: "failed_to_import_srt_file"))
        }
    }
    
    // MARK: - .yomi 附带导入
    
    /// .yomi ファイルをインポートし、pendingAudioSource と組み合わせてプレーヤーに遷移する
    func attachYomi(url: URL) {
        guard let source = pendingAudioSource else { return }
        do {
            let importedDoc = try SubtitleExportService.readYomiFile(from: url)
            let doc = TranscriptDocument(
                source: source,
                segments: importedDoc.segments
            )
            try DocumentStore.shared.save(doc)
            loadSavedDocuments()
            pendingAudioSource = nil
            showSRTOption = false
            navigateToPlayerDocument = doc
            navigateToPlayer = true
        } catch {
            showErrorMessage(String(localized: "yomi_import_error"))
        }
    }
    
    private func isVideoFile(url: URL) -> Bool {
        ["mp4", "mov", "m4v", "avi", "mkv", "webm"].contains(url.pathExtension.lowercased())
    }
    
    private func extractAudioFromVideo(sourceURL: URL, title: String) {
        isLoadingVideo = true
        Task {
            do {
                let outputURL = try await performAudioExtraction(from: sourceURL)
                await MainActor.run {
                    isLoadingVideo = false
                    promptSRTOption(for: AudioSource(
                        type: .local,
                        localURL: outputURL,
                        relativeFilePath: outputURL.lastPathComponent,
                        title: title,
                        videoRelativeFilePath: sourceURL.lastPathComponent
                    ))
                }
            } catch {
                await MainActor.run {
                    isLoadingVideo = false
                    promptSRTOption(for: AudioSource(type: .local, localURL: sourceURL, title: title))
                }
            }
        }
    }
    
    private func performAudioExtraction(from videoURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let outputURL = documentsURL.appendingPathComponent("extracted_\(UUID().uuidString).m4a")
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw NSError(domain: "HomeViewModel", code: -1)
        }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        await exportSession.export()
        if exportSession.status == .completed { return outputURL }
        throw exportSession.error ?? NSError(domain: "HomeViewModel", code: -2)
    }
    
    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }
    
    // MARK: - ZIP インポート
    
    private static let mediaExtensions = ["mp4", "mov", "m4v", "mp3", "m4a", "wav", "aiff", "avi", "mkv", "webm"]
    private static let srtExtension = "srt"
    private static let yomiExtensions = ["yomi", "json"]
    
    /// ZIP を解凍し、メディア＋字幕を同名でマッチしてフォルダとドキュメントを作成する
    func handleZipImport(url: URL) {
        isImportingZip = true
        zipImportProgressMessage = String(localized: "extracting_zip")
        let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folderName = url.deletingPathExtension().lastPathComponent
        if folderName.isEmpty {
            isImportingZip = false
            showErrorMessage(String(localized: "invalid_zip_file"))
            return
        }
        Task {
            do {
                let destDir = try ZipExtractService.extract(zipURL: url, destinationParent: docsURL, folderName: folderName)
                await MainActor.run { zipImportProgressMessage = String(localized: "matching_files") }
                
                let contents = try FileManager.default.contentsOfDirectory(at: destDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
                var mediaByBase: [String: URL] = [:]
                var srtByBase: [String: URL] = [:]
                var yomiByBase: [String: URL] = [:]
                let impRel = "Imports/\(folderName)"
                for url in contents {
                    let ext = url.pathExtension.lowercased()
                    let base = url.deletingPathExtension().lastPathComponent
                    if Self.mediaExtensions.contains(ext) {
                        mediaByBase[base] = url
                    } else if ext == Self.srtExtension {
                        srtByBase[base] = url
                    } else if Self.yomiExtensions.contains(ext) {
                        yomiByBase[base] = url
                    }
                }
                
                let folder = TranscriptFolder(name: folderName)
                try DocumentStore.shared.addFolder(folder)
                let furiganaService = CFStringTokenizerFuriganaService()
                var created = 0
                let baseNames = Set(mediaByBase.keys).sorted()
                for base in baseNames {
                    guard let mediaURL = mediaByBase[base] else { continue }
                    let relPath = "\(impRel)/\(mediaURL.lastPathComponent)"
                    let title = base
                    var doc: TranscriptDocument?
                    // 配对规则：仅 .srt → 用 .srt；仅 .yomi → 用 .yomi；同时有 .srt 与 .yomi → 优先 .yomi
                    let hasYomi = yomiByBase[base] != nil
                    let hasSrt = srtByBase[base] != nil
                    if hasYomi {
                        // 有 .yomi（无论是否同时有 .srt，都优先用 .yomi）
                        let yomiURL = yomiByBase[base]!
                        let imported = try SubtitleExportService.readYomiFile(from: yomiURL)
                        var source = AudioSource(
                            type: .local,
                            localURL: mediaURL,
                            relativeFilePath: relPath,
                            title: title
                        )
                        if isVideoFile(url: mediaURL) {
                            source.videoRelativeFilePath = relPath
                        }
                        doc = TranscriptDocument(source: source, segments: imported.segments, folderId: folder.id)
                    } else if hasSrt {
                        // 仅有 .srt（无 .yomi 时用 .srt）
                        let srtURL = srtByBase[base]!
                        let srtSegments = try SubtitleImportService.parseSRT(from: srtURL)
                        var segments: [TranscriptSegment] = []
                        for seg in srtSegments {
                            let tokens = await furiganaService.generateFurigana(for: seg.text)
                            segments.append(TranscriptSegment(
                                startTime: seg.startTime,
                                endTime: seg.endTime,
                                originalText: seg.text,
                                tokens: tokens
                            ))
                        }
                        var source = AudioSource(
                            type: .local,
                            localURL: mediaURL,
                            relativeFilePath: relPath,
                            title: title
                        )
                        if isVideoFile(url: mediaURL) {
                            source.videoRelativeFilePath = relPath
                        }
                        doc = TranscriptDocument(source: source, segments: segments, folderId: folder.id)
                    }
                    if let d = doc {
                        try DocumentStore.shared.save(d)
                        created += 1
                    }
                }
                await MainActor.run {
                    loadSavedDocuments()
                    isImportingZip = false
                    zipImportProgressMessage = ""
                    if created == 0 {
                        showErrorMessage(String(localized: "zip_no_matching_pairs"))
                    }
                }
            } catch {
                await MainActor.run {
                    isImportingZip = false
                    zipImportProgressMessage = ""
                    showErrorMessage(String(localized: "zip_import_error") + ": " + error.localizedDescription)
                }
            }
        }
    }
}

struct VideoTransferable: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let dest = docs.appendingPathComponent("video_\(UUID().uuidString).\(received.file.pathExtension)")
            try FileManager.default.copyItem(at: received.file, to: dest)
            return VideoTransferable(url: dest)
        }
    }
}
