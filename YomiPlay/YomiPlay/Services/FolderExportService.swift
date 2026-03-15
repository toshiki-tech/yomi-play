//
//  FolderExportService.swift
//  YomiPlay
//
//  将分组内的音视频 + 字幕打包为 ZIP，便于分享；格式与「从ZIP导入」兼容。
//

import Foundation
import ZIPFoundation

enum FolderExportService {

    /// 将指定文档列表打包为同名媒体 + .yomi 的 ZIP，返回临时 ZIP 的 URL。调用方分享后需删除该文件。
    /// - Parameters:
    ///   - documents: 该分组内的文档（需含本地媒体）
    ///   - folderName: 分组名，用作 ZIP 文件名
    /// - Returns: 临时 ZIP 文件 URL，失败或无有效文档时 throw
    static func createZip(documents: [TranscriptDocument], folderName: String) throws -> URL {
        let fm = FileManager.default
        let parentDir = fm.temporaryDirectory.appendingPathComponent("YomiPlayExport", isDirectory: true)
        if !fm.fileExists(atPath: parentDir.path) {
            try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }
        let workDir = parentDir.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workDir) }

        let safeFolderName = sanitizeFileName(folderName)
        var usedBaseNames: Set<String> = []
        var addedCount = 0

        for doc in documents {
            let mediaURL = doc.source.videoPlaybackURL ?? doc.source.playbackURL
            guard let media = mediaURL, fm.fileExists(atPath: media.path) else { continue }

            let baseName = uniqueBaseName(from: doc.source.title, used: &usedBaseNames)
            let ext = media.pathExtension.isEmpty ? "bin" : media.pathExtension
            let destMedia = workDir.appendingPathComponent("\(baseName).\(ext)")
            try fm.copyItem(at: media, to: destMedia)

            if let yomiURL = SubtitleExportService.writeYomiToTempFile(document: doc, fileName: baseName) {
                let destYomi = workDir.appendingPathComponent("\(baseName).yomi")
                try? fm.copyItem(at: yomiURL, to: destYomi)
                try? fm.removeItem(at: yomiURL)
            }
            addedCount += 1
        }

        guard addedCount > 0 else {
            throw NSError(domain: "FolderExport", code: -1, userInfo: [NSLocalizedDescriptionKey: String(localized: "folder_export_no_media")])
        }

        let zipName = safeFolderName.isEmpty ? "Export" : safeFolderName
        let zipURL = parentDir.appendingPathComponent("\(zipName).zip")
        if fm.fileExists(atPath: zipURL.path) {
            try fm.removeItem(at: zipURL)
        }
        try fm.zipItem(at: workDir, to: zipURL)
        return zipURL
    }

    private static func sanitizeFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return name
            .components(separatedBy: invalid)
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func uniqueBaseName(from title: String, used: inout Set<String>) -> String {
        var base = sanitizeFileName(title)
        if base.isEmpty { base = "item" }
        var name = base
        var n = 1
        while used.contains(name) {
            n += 1
            name = "\(base)_\(n)"
        }
        used.insert(name)
        return name
    }
}
