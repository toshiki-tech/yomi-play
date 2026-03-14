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
            let url = docs.appendingPathComponent(rel)
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
                print("DocumentStore: メディア削除 \(rel)")
            }
        }
        if let rel = document.source.videoRelativeFilePath, !rel.isEmpty {
            let url = docs.appendingPathComponent(rel)
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
                print("DocumentStore: 動画削除 \(rel)")
            }
        }
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
    
    /// 全フォルダを読み込む
    func loadAllFolders() -> [TranscriptFolder] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: foldersFileURL),
              let folders = try? decoder.decode([TranscriptFolder].self, from: data)
        else { return [] }
        return folders.sorted { $0.createdAt > $1.createdAt }
    }
    
    /// フォルダ一覧を保存する
    func saveFolders(_ folders: [TranscriptFolder]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(folders)
        try data.write(to: foldersFileURL)
    }
    
    /// フォルダを追加する
    func addFolder(_ folder: TranscriptFolder) throws {
        var folders = loadAllFolders()
        folders.insert(folder, at: 0)
        try saveFolders(folders)
    }
    
    /// フォルダを削除する（ドキュメントの folderId は呼び出し側で nil にすること）
    func deleteFolder(id: UUID) throws {
        var folders = loadAllFolders().filter { $0.id != id }
        try saveFolders(folders)
    }
    
    /// フォルダ名を更新する
    func updateFolder(_ folder: TranscriptFolder) throws {
        var folders = loadAllFolders()
        guard let idx = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        folders[idx] = folder
        try saveFolders(folders)
    }
}
