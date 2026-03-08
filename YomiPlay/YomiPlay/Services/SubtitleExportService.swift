//
//  SubtitleExportService.swift
//  YomiPlay
//
//  字幕を SRT 形式でエクスポートする
//

import Foundation

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
}
