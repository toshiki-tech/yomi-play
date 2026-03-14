//
//  RemoteMediaResolver.swift
//  YomiPlay
//
//  解析用户传入的远程链接类型，并尝试得到可下载的音频地址。
//  定位：从公开播客/远程音频源解析出真实资源，不涉及任何“官方播客下载”能力。
//

import Foundation

/// 远程来源类型（用于区分链接种类，便于提示与风控）
enum RemoteSourceKind: String, Sendable {
    case directAudio       // 直接音频 URL
    case rssFeed           // RSS feed
    case episodePage       // 单集/节目页
    case applePodcastPage  // 播客目录/节目页（仅作分类，不承诺“官方”能力）
    case webpage           // 普通网页
    case unsupported       // 不支持或无法解析
}

/// 解析后的远程媒体信息
struct ResolvedRemoteMedia: Sendable {
    let originalURL: URL
    /// 最终可请求的音频 URL（若为 feed 则解析出单集 enclosure）
    let resolvedAudioURL: URL?
    let sourceKind: RemoteSourceKind
    let title: String?
    let mimeType: String?
    /// 是否需要先下载再使用
    var requiresDownload: Bool { resolvedAudioURL != nil && sourceKind != .unsupported }
    var isSupported: Bool { sourceKind != .unsupported && resolvedAudioURL != nil }
}

enum RemoteSourceError: LocalizedError, Sendable {
    case unsupportedURL
    case cannotResolveAudio
    case invalidFeed
    case blockedSource

    var errorDescription: String? {
        switch self {
        case .unsupportedURL: return String(localized: "podcast_link_unresolvable")
        case .cannotResolveAudio: return String(localized: "podcast_link_unresolvable")
        case .invalidFeed: return String(localized: "podcast_link_unresolvable")
        case .blockedSource: return String(localized: "podcast_link_unresolvable")
        }
    }
}

// MARK: - 音频扩展名 / MIME 判断

private let audioPathExtensions: Set<String> = [
    "mp3", "m4a", "aac", "wav", "ogg", "flac", "opus", "weba"
]

private let streamingExtensions: Set<String> = ["m3u8", "m3u"]

enum RemoteMediaResolver {

    /// 解析远程链接，得到可下载的音频 URL 及来源类型。
    /// - Parameter url: 用户输入的链接（可能是直接音频、RSS、节目页等）
    /// - Returns: 解析结果，若无法得到音频地址则 isSupported == false
    static func resolve(originalURL: URL) async -> ResolvedRemoteMedia {
        let trimmed = originalURL.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme == "https" || url.scheme == "http" else {
            return ResolvedRemoteMedia(originalURL: originalURL, resolvedAudioURL: nil, sourceKind: .unsupported, title: nil, mimeType: nil)
        }

        let ext = url.pathExtension.lowercased()
        if streamingExtensions.contains(ext) {
            return ResolvedRemoteMedia(originalURL: url, resolvedAudioURL: nil, sourceKind: .unsupported, title: nil, mimeType: "application/vnd.apple.mpegurl")
        }
        if audioPathExtensions.contains(ext) {
            return ResolvedRemoteMedia(originalURL: url, resolvedAudioURL: url, sourceKind: .directAudio, title: url.deletingPathExtension().lastPathComponent, mimeType: nil)
        }

        // RSS / XML feed：拉取并解析第一个 enclosure
        if ext == "xml" || ext == "rss" || url.absoluteString.lowercased().contains("feed") || url.absoluteString.lowercased().contains("rss") {
            if let enclosure = await firstAudioEnclosure(fromFeed: url) {
                return ResolvedRemoteMedia(originalURL: url, resolvedAudioURL: enclosure.url, sourceKind: .rssFeed, title: enclosure.title, mimeType: nil)
            }
            return ResolvedRemoteMedia(originalURL: url, resolvedAudioURL: nil, sourceKind: .rssFeed, title: nil, mimeType: nil)
        }

        // 播客目录/节目页（如 podcasts.apple.com）：仅作分类，不解析 HTML
        if url.host?.lowercased().contains("podcasts.apple.com") == true || url.host?.lowercased().contains("itunes.apple.com") == true {
            return ResolvedRemoteMedia(originalURL: url, resolvedAudioURL: nil, sourceKind: .applePodcastPage, title: nil, mimeType: nil)
        }

        // 其他：尝试 HEAD 看 Content-Type
        if let (finalURL, contentType) = await fetchContentType(for: url) {
            if contentType.lowercased().hasPrefix("audio/") {
                return ResolvedRemoteMedia(originalURL: url, resolvedAudioURL: finalURL, sourceKind: .directAudio, title: url.deletingPathExtension().lastPathComponent, mimeType: contentType)
            }
            if contentType.lowercased().contains("rss") || contentType.lowercased().contains("xml") {
                if let enclosure = await firstAudioEnclosure(fromFeed: finalURL) {
                    return ResolvedRemoteMedia(originalURL: url, resolvedAudioURL: enclosure.url, sourceKind: .rssFeed, title: enclosure.title, mimeType: nil)
                }
            }
            if contentType.lowercased().contains("html") {
                return ResolvedRemoteMedia(originalURL: url, resolvedAudioURL: nil, sourceKind: .webpage, title: nil, mimeType: contentType)
            }
        }

        return ResolvedRemoteMedia(originalURL: url, resolvedAudioURL: nil, sourceKind: .unsupported, title: nil, mimeType: nil)
    }

    private static func fetchContentType(for url: URL) async -> (URL, String)? {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.setValue(RemoteAudioFetcher.compatibilityUserAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let ct = http.value(forHTTPHeaderField: "Content-Type")?.split(separator: ";").first.map(String.init) else { return nil }
            return (url, ct)
        } catch {
            return nil
        }
    }

    private static func firstAudioEnclosure(fromFeed feedURL: URL) async -> (url: URL, title: String?)? {
        var request = URLRequest(url: feedURL)
        request.setValue(RemoteAudioFetcher.compatibilityUserAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let delegate = FirstEnclosureParser()
            let parser = XMLParser(data: data)
            parser.delegate = delegate
            parser.parse()
            return delegate.firstEnclosure
        } catch {
            return nil
        }
    }
}

private final class FirstEnclosureParser: NSObject, XMLParserDelegate {
    var firstEnclosure: (url: URL, title: String?)?
    private var inItem = false
    private var currentTitle = ""
    private var currentElement = ""
    private var enclosureURL: URL?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        if elementName == "item" {
            inItem = true
            currentTitle = ""
            enclosureURL = nil
        }
        if inItem && elementName == "enclosure" {
            if let urlString = attributeDict["url"], let url = URL(string: urlString),
               let type = attributeDict["type"], type.hasPrefix("audio/") {
                enclosureURL = url
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inItem, currentElement == "title" else { return }
        currentTitle += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "item", let url = enclosureURL, firstEnclosure == nil {
            firstEnclosure = (url, currentTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : currentTitle.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
