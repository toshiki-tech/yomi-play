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
        case .dateNewestFirst: return String(localized: "日期（从新到旧）")
        case .dateOldestFirst: return String(localized: "日期（从旧到新）")
        case .titleAscending: return String(localized: "名称（升序）")
        case .titleDescending: return String(localized: "名称（降序）")
        case .segmentCountDescending: return String(localized: "片段数（从多到少）")
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
    
    // 検索・フィルタリング
    var searchText: String = ""
    /// 一覧の並び順
    var sortOrder: DocumentSortOrder = .dateNewestFirst
    private var allSavedDocuments: [TranscriptDocument] = []
    
    // ナビゲーション
    var selectedAudioSource: AudioSource?
    var navigateToProcessing: Bool = false
    
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
            showErrorMessage(String(localized: "重命名失败") + ": " + error.localizedDescription)
        }
        
        documentToRename = nil
        showRenameAlert = false
    }
    
    // MARK: - インポート処理（既存のロジックを保持）
    
    func handleFileSelected(result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else {
                showErrorMessage(String(localized: "没有文件访问权限"))
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
                    selectedAudioSource = AudioSource(
                        type: .local,
                        localURL: destinationURL,
                        relativeFilePath: destinationURL.lastPathComponent,
                        title: url.deletingPathExtension().lastPathComponent
                    )
                    navigateToProcessing = true
                }
            } catch {
                url.stopAccessingSecurityScopedResource()
                showErrorMessage(String(localized: "文件复制失败"))
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
                    await MainActor.run { isLoadingVideo = false; showErrorMessage(String(localized: "加载失败")) }
                    return
                }
                let videoTitle = String(localized: "相册视频")
                await MainActor.run {
                    if isVideoFile(url: videoData.url) {
                        extractAudioFromVideo(sourceURL: videoData.url, title: videoTitle)
                    } else {
                        selectedAudioSource = AudioSource(
                            type: .local,
                            localURL: videoData.url,
                            relativeFilePath: videoData.url.lastPathComponent,
                            title: videoTitle
                        )
                        isLoadingVideo = false
                        navigateToProcessing = true
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
        selectedAudioSource = AudioSource(type: .remote, remoteURL: url, title: url.deletingPathExtension().lastPathComponent)
        navigateToProcessing = true
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
                    selectedAudioSource = AudioSource(
                        type: .local,
                        localURL: outputURL,
                        relativeFilePath: outputURL.lastPathComponent,
                        title: title
                    )
                    isLoadingVideo = false
                    navigateToProcessing = true
                }
            } catch {
                await MainActor.run {
                    selectedAudioSource = AudioSource(type: .local, localURL: sourceURL, title: title)
                    isLoadingVideo = false
                    navigateToProcessing = true
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
