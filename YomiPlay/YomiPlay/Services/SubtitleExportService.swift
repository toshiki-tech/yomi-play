//
//  SubtitleExportService.swift
//  YomiPlay
//
//  字幕を SRT 形式でエクスポートする
//

import Foundation
import UniformTypeIdentifiers

extension UTType {
    static var yomiDocument: UTType {
        UTType(exportedAs: "com.yomiplay.yomi", conformingTo: .json)
    }
}

enum SubtitleExportService {
    
    /// 秒を SRT のタイムスタンプ形式（HH:MM:SS,mmm）に変換
    private static func srtTimestamp(from seconds: TimeInterval) -> String {
        let totalMs = Int(seconds * 1000)
        let ms = totalMs % 1000
        let s = (totalMs / 1000) % 60
        let m = (totalMs / 60_000) % 60
        let h = totalMs / 3_600_000
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, ms)
    }
    
    /// セグメント配列から SRT 形式の文字列を生成する
    static func exportSRT(segments: [TranscriptSegment]) -> String {
        var lines: [String] = []
        for (index, segment) in segments.enumerated() {
            lines.append("\(index + 1)")
            lines.append("\(srtTimestamp(from: segment.startTime)) --> \(srtTimestamp(from: segment.endTime))")
            lines.append(segment.originalText)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
    
    /// SRT を一時ファイルに書き込み、その URL を返す。呼び出し側で共有後に削除すること
    static func writeSRTToTempFile(segments: [TranscriptSegment], fileName: String = "subtitles") -> URL? {
        let srt = exportSRT(segments: segments)
        let safeName = fileName.isEmpty ? "subtitles" : fileName
            .components(separatedBy: .illegalCharacters).joined()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName).srt")
        do {
            try srt.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
    
    // MARK: - .yomi 形式（完全なメタデータ付き JSON）
    
    /// TranscriptDocument を .yomi ファイルとして一時ディレクトリに書き出す
    static func writeYomiToTempFile(document: TranscriptDocument, fileName: String = "subtitles") -> URL? {
        var exportDoc = document
        exportDoc.source.localURL = nil
        exportDoc.source.remoteURL = nil
        exportDoc.source.relativeFilePath = nil
        exportDoc.source.srtRelativeFilePath = nil
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        guard let data = try? encoder.encode(exportDoc) else { return nil }
        
        let safeName = fileName.isEmpty ? "subtitles" : fileName
            .components(separatedBy: .illegalCharacters).joined()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName).yomi")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
    
    /// .yomi ファイルを読み込み TranscriptDocument として返す
    static func readYomiFile(from url: URL) throws -> TranscriptDocument {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
        
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TranscriptDocument.self, from: data)
    }
}
