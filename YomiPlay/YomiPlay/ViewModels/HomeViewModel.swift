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

/// ZIP インポート成功時の表示用（Equatable で onChange に使用）
struct ZipImportSuccessInfo: Equatable {
    var folderName: String
    var count: Int
}

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
    /// ZIP インポート成功時の表示（nil で非表示）
    var zipImportSuccessInfo: ZipImportSuccessInfo?
    /// 成功后切换到 Library タブ
    var requestSwitchToLibraryTab: Bool = false
    /// 成功后跳转到指定フォルダ
    var zipImportNavigateToFolderId: UUID?

    /// 从分组内触发导入时，期望写入的目标分组 ID（nil = 默认分组）
    var currentImportFolderId: UUID?
    /// 请求切换到导入 Tab（例如在分组内点“导入到本分组”时）
    var requestSwitchToImportTab: Bool = false
    
    /// 分组导出为 ZIP 分享：生成的临时 ZIP URL，分享结束后需清理
    var exportedZipURL: URL?
    var showShareZipSheet: Bool = false

    /// 是否展示订阅墙（权限不足时弹出）
    var showPaywall: Bool = false
    
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
    
    /// 検索フィルタ（分组名 OR 记录标题/字幕）＋並び順適用済みのドキュメント一覧
    var filteredDocuments: [TranscriptDocument] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let list: [TranscriptDocument]
        if query.isEmpty {
            list = allSavedDocuments
        } else {
            list = allSavedDocuments.filter { doc in
                let recordMatches = doc.source.title.localizedCaseInsensitiveContains(query)
                    || doc.segments.contains { $0.originalText.localizedCaseInsensitiveContains(query) }
                if recordMatches { return true }
                if let fid = doc.folderId, let folder = allFolders.first(where: { $0.id == fid }) {
                    return folder.name.localizedCaseInsensitiveContains(query)
                }
                return false
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
    
    /// フォルダを削除する（配下のドキュメントもまとめて削除する）
    func deleteFolder(_ folder: TranscriptFolder) {
        // 先に该分组下的所有记录整体删除（包括其关联的媒体文件）
        let docsInFolder = allSavedDocuments.filter { $0.folderId == folder.id }
        for doc in docsInFolder {
            try? DocumentStore.shared.delete(id: doc.id)
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
    
    /// 将分组导出为 ZIP 并触发分享（异步）；使用该分组内全部文档，不受搜索过滤影响
    func exportFolderAsZip(folderId: UUID?) {
        guard SubscriptionManager.shared.isProUser else {
            showPaywall = true
            return
        }
        let docs = allSavedDocuments.filter { $0.folderId == folderId }
        let name = folderDisplayName(for: folderId)
        guard !docs.isEmpty else {
            showErrorMessage(String(localized: "folder_export_no_media"))
            return
        }
        Task {
            do {
                let url = try FolderExportService.createZip(documents: docs, folderName: name)
                await MainActor.run {
                    exportedZipURL = url
                    showShareZipSheet = true
                }
            } catch {
                await MainActor.run { showErrorMessage(error.localizedDescription) }
            }
        }
    }
    
    /// 分享结束或取消后清理临时 ZIP
    func clearExportedZip() {
        if let url = exportedZipURL {
            try? FileManager.default.removeItem(at: url)
        }
        exportedZipURL = nil
        showShareZipSheet = false
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
            if isVideoFile(url: url), !SubscriptionManager.shared.isProUser {
                showPaywall = true
                return
            }
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
                        title: url.deletingPathExtension().lastPathComponent,
                        folderId: currentImportFolderId
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
        if !SubscriptionManager.shared.isProUser {
            showPaywall = true
            return
        }
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
                            title: videoTitle,
                            folderId: currentImportFolderId
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
        startImportFromURL(url, title: url.deletingPathExtension().lastPathComponent)
    }
    
    /// 从指定 URL 开始导入（用于手动输入 URL），弹出 SRT 选项后进入处理
    func startImportFromURL(_ url: URL, title: String) {
        promptSRTOption(for: AudioSource(type: .remote, remoteURL: url, title: title, folderId: currentImportFolderId))
    }

    /// 直接开始处理（不弹字幕选项），用于播客导入等场景，一律走 AI 语音识别
    func startImportFromURLDirect(_ url: URL, title: String) {
        let source = AudioSource(type: .remote, remoteURL: url, title: title, folderId: currentImportFolderId)
        selectedAudioSource = source
        navigateToProcessing = true
    }
    
    // MARK: - SRT 附带导入
    
    /// 音视频选择完成后，弹出是否附带 SRT 的选项
    func promptSRTOption(for source: AudioSource) {
        pendingAudioSource = source
        showSRTOption = true
    }
    
    /// 用户选择跳过 SRT，直接进入处理流程（免费用户先检查本月识别时长配额）
    func skipSRT() {
        guard let source = pendingAudioSource else { return }
        Task {
            var durationSeconds = 0
            if let url = source.playbackURL, source.type == .local {
                durationSeconds = await SubscriptionManager.durationSeconds(of: url)
            }
            guard SubscriptionManager.shared.canUseRecognitionSeconds(durationSeconds) else {
                await MainActor.run {
                    showPaywall = true
                }
                return
            }
            await MainActor.run {
                selectedAudioSource = source
                pendingAudioSource = nil
                showSRTOption = false
                navigateToProcessing = true
            }
        }
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
                        videoRelativeFilePath: sourceURL.lastPathComponent,
                        folderId: currentImportFolderId
                    ))
                }
            } catch {
                await MainActor.run {
                    isLoadingVideo = false
                    promptSRTOption(for: AudioSource(type: .local, localURL: sourceURL, title: title, folderId: currentImportFolderId))
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
        try await exportSession.export(to: outputURL, as: .m4a)
        return outputURL
    }
    
    func showErrorMessage(_ message: String) {
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
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let contentRoot = try ZipExtractService.extract(zipURL: url, destinationParent: docsURL, folderName: folderName)
                await MainActor.run { zipImportProgressMessage = String(localized: "matching_files") }
                
                let contents = try FileManager.default.contentsOfDirectory(at: contentRoot, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
                var mediaByBase: [String: URL] = [:]
                var srtByBase: [String: URL] = [:]
                var yomiByBase: [String: URL] = [:]
                for itemURL in contents {
                    let ext = itemURL.pathExtension.lowercased()
                    let base = itemURL.deletingPathExtension().lastPathComponent
                    if Self.mediaExtensions.contains(ext) {
                        mediaByBase[base] = itemURL
                    } else if ext == Self.srtExtension {
                        srtByBase[base] = itemURL
                    } else if Self.yomiExtensions.contains(ext) {
                        yomiByBase[base] = itemURL
                    }
                }
                
                let folder = TranscriptFolder(name: folderName)
                try DocumentStore.shared.addFolder(folder)
                let furiganaService = CFStringTokenizerFuriganaService()
                var created = 0
                let baseNames = Set(mediaByBase.keys).sorted()
                for base in baseNames {
                    guard let mediaURL = mediaByBase[base] else { continue }
                    var relPath = mediaURL.path
                    let docsPath = docsURL.path
                    if relPath.hasPrefix(docsPath) {
                        relPath = String(relPath.dropFirst(docsPath.count))
                        if relPath.hasPrefix("/") { relPath = String(relPath.dropFirst(1)) }
                    } else {
                        relPath = "Imports/\(folderName)/\(mediaURL.lastPathComponent)"
                    }
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
                            let isJapanese = WhisperSpeechRecognitionService.isLikelyJapanese(seg.text)
                            let tokens = isJapanese ? await furiganaService.generateFurigana(for: seg.text) : []
                            segments.append(TranscriptSegment(
                                startTime: seg.startTime,
                                endTime: seg.endTime,
                                originalText: seg.text,
                                tokens: tokens,
                                skipFurigana: !isJapanese
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
                    } else {
                        zipImportSuccessInfo = ZipImportSuccessInfo(folderName: folderName, count: created)
                        requestSwitchToLibraryTab = true
                        zipImportNavigateToFolderId = folder.id
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
