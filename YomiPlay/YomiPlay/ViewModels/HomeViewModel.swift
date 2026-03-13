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
    }
    var fileImportMode: FileImportMode = .audioVideo
    
    // 検索・フィルタリング
    var searchText: String = ""
    /// 一覧の並び順
    var sortOrder: DocumentSortOrder = .dateNewestFirst
    private var allSavedDocuments: [TranscriptDocument] = []
    
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
    
    init() {
        loadSavedDocuments()
    }
    
    /// 保存済みドキュメントを読み込む
    func loadSavedDocuments() {
        allSavedDocuments = DocumentStore.shared.loadAll()
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
