//
//  ZipExtractService.swift
//  YomiPlay
//
//  ZIP 解凍：Documents/Imports/<name>/ に展開する。
//  macOS 右键压缩等标准 ZIP（含 deflate）使用 ZIPFoundation 解压，避免自研 deflate 与系统生成格式不兼容。
//

import Foundation
import ZIPFoundation

enum ZipExtractService {

    /// ZIP を解凍し、展開先の「実質的な内容ルート」URL を返す。失敗時は throw
    /// 调用方需在传入前已调用 zipURL.startAccessingSecurityScopedResource()
    /// 流程：先复制到临时文件 → 使用 ZIPFoundation 解压到目标目录 → 解析内容根目录 → 删除临时文件
    static func extract(zipURL: URL, destinationParent: URL, folderName: String) throws -> URL {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("YomiPlayZip", isDirectory: true)
        if !fm.fileExists(atPath: tempDir.path) {
            try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        }
        let tempZipURL = tempDir.appendingPathComponent(UUID().uuidString + ".zip")
        defer { try? fm.removeItem(at: tempZipURL) }
        try fm.copyItem(at: zipURL, to: tempZipURL)

        let destDir = destinationParent
            .appendingPathComponent("Imports", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)

        if fm.fileExists(atPath: destDir.path) {
            try fm.removeItem(at: destDir)
        }
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)

        try fm.unzipItem(at: tempZipURL, to: destDir)

        return resolveContentRoot(destDir)
    }

    /// 判断实际内容根目录：若解压后仅有一个子文件夹且根目录无文件，则返回该子目录；否则返回 destDir
    private static func resolveContentRoot(_ destDir: URL) -> URL {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: destDir, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles),
              !items.isEmpty else { return destDir }
        let dirs = items.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        let files = items.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true }
        if dirs.count == 1, files.isEmpty {
            return dirs[0]
        }
        return destDir
    }
}
