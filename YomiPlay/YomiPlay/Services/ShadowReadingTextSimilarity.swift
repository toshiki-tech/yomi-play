//
//  ShadowReadingTextSimilarity.swift
//  YomiPlay
//
//  跟读评分：归一化后按字符级 Levenshtein 得 0–100 近似相似度（非发音评测）
//

import Foundation

enum ShadowReadingTextSimilarity {

    /// 用于比对的归一化：去空白、全半角统一、小写（拉丁）
    static func normalize(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let m = NSMutableString(string: t)
        CFStringTransform(m, nil, kCFStringTransformFullwidthHalfwidth, false)
        t = String(m)
        t = t.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        return t.lowercased()
    }

    /// 0–100，100 为完全一致（在 normalize 意义下）
    static func scorePercent(reference: String, hypothesis: String) -> Int {
        let a = normalize(reference)
        let b = normalize(hypothesis)
        if a.isEmpty, b.isEmpty { return 100 }
        if a.isEmpty || b.isEmpty { return 0 }
        let d = levenshteinDistance(a, b)
        let denom = max(a.count, b.count)
        let ratio = 1.0 - Double(d) / Double(denom)
        return max(0, min(100, Int((ratio * 100.0).rounded(.toNearestOrAwayFromZero))))
    }

    private static func levenshteinDistance(_ a: String, _ b: String) -> Int {
        let ac = Array(a)
        let bc = Array(b)
        let n = ac.count
        let m = bc.count
        if n == 0 { return m }
        if m == 0 { return n }
        var row = Array(0...m)
        for i in 1...n {
            var previous = row[0]
            row[0] = i
            for j in 1...m {
                let temp = row[j]
                let cost = ac[i - 1] == bc[j - 1] ? 0 : 1
                row[j] = min(
                    row[j] + 1,
                    row[j - 1] + 1,
                    previous + cost
                )
                previous = temp
            }
        }
        return row[m]
    }
}
