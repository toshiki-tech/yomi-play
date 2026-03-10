//
//  SubtitleImportService.swift
//  YomiPlay
//
//  SRT 字幕ファイルを解析してインポートする
//

import Foundation

struct SRTSegment {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
}

enum SubtitleImportService {
    
    /// SRT ファイルを解析し、タイムスタンプ付きセグメント配列を返す
    static func parseSRT(from url: URL) throws -> [SRTSegment] {
        let content: String
        if url.startAccessingSecurityScopedResource() {
            defer { url.stopAccessingSecurityScopedResource() }
            content = try String(contentsOf: url, encoding: .utf8)
        } else {
            content = try String(contentsOf: url, encoding: .utf8)
        }
        return parseSRTContent(content)
    }
    
    /// SRT 形式のテキストを解析する
    static func parseSRTContent(_ content: String) -> [SRTSegment] {
        var segments: [SRTSegment] = []
        let blocks = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n\n")
        
        for block in blocks {
            let lines = block.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: "\n")
            guard lines.count >= 2 else { continue }
            
            // タイムスタンプ行を探す（"-->" を含む行）
            guard let timeLineIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let timeLine = lines[timeLineIndex]
            
            let timeParts = timeLine.components(separatedBy: "-->")
            guard timeParts.count == 2,
                  let startTime = parseSRTTimestamp(timeParts[0].trimmingCharacters(in: .whitespaces)),
                  let endTime = parseSRTTimestamp(timeParts[1].trimmingCharacters(in: .whitespaces))
            else { continue }
            
            // タイムスタンプ行以降のすべてのテキスト行を結合
            let textLines = lines[(timeLineIndex + 1)...]
            let text = textLines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            
            segments.append(SRTSegment(startTime: startTime, endTime: endTime, text: text))
        }
        
        return segments.sorted { $0.startTime < $1.startTime }
    }
    
    /// SRT タイムスタンプ文字列（HH:MM:SS,mmm）を秒に変換する
    /// "." 区切りにも対応
    static func parseSRTTimestamp(_ str: String) -> TimeInterval? {
        let normalized = str.replacingOccurrences(of: ",", with: ".")
        let parts = normalized.components(separatedBy: ":")
        guard parts.count == 3 else { return nil }
        
        guard let hours = Double(parts[0].trimmingCharacters(in: .whitespaces)),
              let minutes = Double(parts[1].trimmingCharacters(in: .whitespaces))
        else { return nil }
        
        let secParts = parts[2].trimmingCharacters(in: .whitespaces)
        guard let seconds = Double(secParts) else { return nil }
        
        return hours * 3600 + minutes * 60 + seconds
    }
}
