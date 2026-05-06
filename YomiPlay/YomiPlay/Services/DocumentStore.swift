//
//  DocumentStore.swift
//  YomiPlay
//
//  字幕ドキュメントの永続化サービス
//  JSON ファイルとして Documents ディレクトリに保存・読み込み・削除する
//

import Foundation

/// 字幕ドキュメントの保存・読み込み・削除を行うストア
final class DocumentStore: @unchecked Sendable {
    
    static let shared = DocumentStore()
    
    /// 保存先ディレクトリ
    private var storeDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("SavedDocuments", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    private var foldersFileURL: URL { storeDirectory.appendingPathComponent("folders.json") }
    /// 各分组内「自定义排序」下的记录 UUID 顺序（key: 分组 UUID 字符串，或 "uncategorized"）
    private var libraryManualOrderFileURL: URL { storeDirectory.appendingPathComponent("libraryManualOrder.json") }
    /// 用户分组（文件夹）在库列表中的显示顺序
    private var libraryFolderOrderFileURL: URL { storeDirectory.appendingPathComponent("libraryFolderOrder.json") }
    
    private init() {}
    
    // MARK: - 保存
    
    /// ドキュメントを保存する
    func save(_ document: TranscriptDocument) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(document)
        let fileURL = storeDirectory.appendingPathComponent("\(document.id.uuidString).json")
        try data.write(to: fileURL)
        print("DocumentStore: 保存完了 id=\(document.id), title=\(document.source.title)")
    }
    
    // MARK: - 読み込み
    
    /// 保存済みドキュメント一覧を取得する（日付降順）
    func loadAll() -> [TranscriptDocument] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        var documents: [TranscriptDocument] = []
        
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: storeDirectory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else {
            return []
        }
        
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let doc = try? decoder.decode(TranscriptDocument.self, from: data) {
                documents.append(doc)
            }
        }
        
        // 日付降順
        documents.sort { $0.createdAt > $1.createdAt }
        return documents
    }
    
    /// 特定のドキュメントを読み込む
    func load(id: UUID) -> TranscriptDocument? {
        let fileURL = storeDirectory.appendingPathComponent("\(id.uuidString).json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        guard let data = try? Data(contentsOf: fileURL),
              let doc = try? decoder.decode(TranscriptDocument.self, from: data) else {
            return nil
        }
        return doc
    }
    
    // MARK: - 削除
    
    /// ドキュメントを削除する（参照している Media 内の音声・動画ファイルも削除し、残りファイルを防ぐ）
    func delete(id: UUID) throws {
        if let doc = load(id: id) {
            removeMediaFilesIfOwned(for: doc)
        }
        let fileURL = storeDirectory.appendingPathComponent("\(id.uuidString).json")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
            print("DocumentStore: 削除完了 id=\(id)")
        }
    }

    /// ドキュメントが参照する音声・動画ファイルが Documents 直下または Media 内にあれば削除する
    private func removeMediaFilesIfOwned(for document: TranscriptDocument) {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        if let rel = document.source.relativeFilePath, !rel.isEmpty {
            removeFileIfUnreferenced(relativePath: rel, excludingDocumentId: document.id, docsRoot: docs, logPrefix: "メディア")
        }
        if let rel = document.source.videoRelativeFilePath, !rel.isEmpty {
            removeFileIfUnreferenced(relativePath: rel, excludingDocumentId: document.id, docsRoot: docs, logPrefix: "動画")
        }
    }

    /// 同一ファイルを複数ドキュメントが参照している場合、誤って削除しないための保護。
    /// - Note: 例えば同名ファイルを複数回インポートすると `relativeFilePath` が同一になりやすい。
    private func removeFileIfUnreferenced(
        relativePath: String,
        excludingDocumentId: UUID,
        docsRoot: URL,
        logPrefix: String
    ) {
        // 他のドキュメントが同じ相対パスを参照しているなら削除しない
        if isRelativePathReferencedByOtherDocuments(relativePath, excludingDocumentId: excludingDocumentId) {
            print("DocumentStore: \(logPrefix)保持（他ドキュメント参照あり） \(relativePath)")
            return
        }
        let url = docsRoot.appendingPathComponent(relativePath)
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
            print("DocumentStore: \(logPrefix)削除 \(relativePath)")
        }
    }

    private func isRelativePathReferencedByOtherDocuments(_ relativePath: String, excludingDocumentId: UUID) -> Bool {
        let all = loadAll()
        for doc in all where doc.id != excludingDocumentId {
            if doc.source.relativeFilePath == relativePath { return true }
            if doc.source.videoRelativeFilePath == relativePath { return true }
        }
        return false
    }
    
    /// 全ドキュメントを削除する
    func deleteAll() throws {
        let files = try FileManager.default.contentsOfDirectory(
            at: storeDirectory,
            includingPropertiesForKeys: nil
        )
        for file in files {
            try FileManager.default.removeItem(at: file)
        }
    }
    
    // MARK: - フォルダ
    
    /// folders.json をそのままデコード（表示順は付けない）
    private func loadRawFoldersFromFile() -> [TranscriptFolder] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: foldersFileURL),
              let folders = try? decoder.decode([TranscriptFolder].self, from: data)
        else { return [] }
        return folders
    }
    
    /// 全フォルダを読み込む（`libraryFolderOrder.json` の順；未設定時は作成日の新しい順に一度だけ書き出し）
    func loadAllFolders() -> [TranscriptFolder] {
        let raw = loadRawFoldersFromFile()
        guard !raw.isEmpty else { return [] }
        var orderedIds = loadLibraryFolderOrder()
        if orderedIds.isEmpty {
            orderedIds = raw.sorted { $0.createdAt > $1.createdAt }.map(\.id)
            try? saveLibraryFolderOrder(orderedIds)
        }
        var dict = Dictionary(uniqueKeysWithValues: raw.map { ($0.id, $0) })
        var result: [TranscriptFolder] = []
        for id in orderedIds {
            if let f = dict.removeValue(forKey: id) { result.append(f) }
        }
        let rest = dict.values.sorted { $0.createdAt > $1.createdAt }
        result.append(contentsOf: rest)
        if !rest.isEmpty {
            try? saveLibraryFolderOrder(result.map(\.id))
        }
        return result
    }
    
    /// フォルダ一覧を保存する（順序は `libraryFolderOrder` で管理するため、配列の並びは任意）
    func saveFolders(_ folders: [TranscriptFolder]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(folders)
        try data.write(to: foldersFileURL)
    }
    
    /// フォルダを追加する
    func addFolder(_ folder: TranscriptFolder) throws {
        var raw = loadRawFoldersFromFile()
        raw.append(folder)
        try saveFolders(raw)
        var order = loadLibraryFolderOrder()
        if order.isEmpty {
            order = raw.sorted { $0.createdAt > $1.createdAt }.map(\.id)
        } else {
            order.insert(folder.id, at: 0)
        }
        try saveLibraryFolderOrder(order)
    }
    
    /// フォルダを削除する（ドキュメントの folderId は呼び出し側で nil にすること）
    func deleteFolder(id: UUID) throws {
        let raw = loadRawFoldersFromFile().filter { $0.id != id }
        try saveFolders(raw)
        var order = loadLibraryFolderOrder()
        order.removeAll { $0 == id }
        try saveLibraryFolderOrder(order)
    }
    
    /// フォルダ名を更新する
    func updateFolder(_ folder: TranscriptFolder) throws {
        var raw = loadRawFoldersFromFile()
        guard let idx = raw.firstIndex(where: { $0.id == folder.id }) else { return }
        raw[idx] = folder
        try saveFolders(raw)
    }
    
    /// 库首页分组列表的文件夹 UUID 顺序
    func loadLibraryFolderOrder() -> [UUID] {
        guard let data = try? Data(contentsOf: libraryFolderOrderFileURL),
              let file = try? JSONDecoder().decode(LibraryFolderOrderFile.self, from: data)
        else { return [] }
        return file.ids
    }
    
    /// 保存库首页分组顺序（仅含用户创建的分组，不含「未分组」）
    func saveLibraryFolderOrder(_ ids: [UUID]) throws {
        let file = LibraryFolderOrderFile(ids: ids)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let data = try encoder.encode(file)
        try data.write(to: libraryFolderOrderFileURL)
    }
    
    // MARK: - 库内自定义排序（按分组存储 UUID 顺序）
    
    /// 读取分组内记录的手动排序表；无文件时返回空字典
    func loadLibraryManualOrder() -> [String: [UUID]] {
        guard let data = try? Data(contentsOf: libraryManualOrderFileURL) else { return [:] }
        let decoder = JSONDecoder()
        guard let wrapper = try? decoder.decode(LibraryManualOrderFile.self, from: data) else { return [:] }
        return wrapper.orders
    }
    
    /// 保存分组内记录的手动排序表
    func saveLibraryManualOrder(_ orders: [String: [UUID]]) throws {
        let wrapper = LibraryManualOrderFile(orders: orders)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let data = try encoder.encode(wrapper)
        try data.write(to: libraryManualOrderFileURL)
    }
}

// MARK: - 手动排序文件包装（便于扩展字段）

private struct LibraryManualOrderFile: Codable {
    var orders: [String: [UUID]]
}

private struct LibraryFolderOrderFile: Codable {
    var ids: [UUID]
}
