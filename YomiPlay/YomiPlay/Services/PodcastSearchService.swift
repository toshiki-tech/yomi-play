//
//  PodcastSearchService.swift
//  YomiPlay
//
//  iTunes Search API 搜索播客 + RSS 解析单集
//

import Foundation

/// iTunes 播客搜索结果
struct PodcastSearchResult: Identifiable {
    let id: Int
    let name: String
    let artistName: String
    let feedURL: URL
    let artworkURL: URL?
}

/// 播客单集（来自 RSS）
struct PodcastEpisode: Identifiable {
    let id: String
    let title: String
    let pubDate: Date?
    let audioURL: URL
}

enum PodcastSearchService {
    private static let searchBase = "https://itunes.apple.com/search"
    private static let limit = 25

    /// 关键词搜索播客节目（iTunes Search API）
    static func search(term: String) async throws -> [PodcastSearchResult] {
        guard !term.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        var comp = URLComponents(string: searchBase)!
        comp.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "media", value: "podcast"),
            URLQueryItem(name: "entity", value: "podcast"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        guard let url = comp.url else { return [] }
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded = try JSONDecoder().decode(iTunesSearchResponse.self, from: data)
        return decoded.results.compactMap { r in
            guard let feed = r.feedUrl.flatMap(URL.init(string:)) else { return nil }
            return PodcastSearchResult(
                id: r.collectionId,
                name: r.collectionName,
                artistName: r.artistName,
                feedURL: feed,
                artworkURL: (r.artworkUrl100 ?? r.artworkUrl600).flatMap { URL(string: $0) }
            )
        }
    }

    /// 获取节目 RSS 中的单集列表（解析 enclosure 作为音频 URL）
    static func fetchEpisodes(feedURL: URL) async throws -> [PodcastEpisode] {
        var request = URLRequest(url: feedURL)
        request.setValue("YomiPlay/1.0", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        return RSSParser.parseEpisodes(data: data, feedURL: feedURL)
    }
}

// MARK: - iTunes API 响应模型

private struct iTunesSearchResponse: Decodable {
    let results: [iTunesPodcastResult]
}

private struct iTunesPodcastResult: Decodable {
    let collectionId: Int
    let collectionName: String
    let artistName: String
    let feedUrl: String?
    let artworkUrl100: String?
    let artworkUrl600: String?
}

// MARK: - RSS 解析

private enum RSSParser {
    /// 解析 RSS/XML 中的 <item>，提取 title、pubDate、enclosure url
    static func parseEpisodes(data: Data, feedURL: URL) -> [PodcastEpisode] {
        let delegate = EpisodeParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.episodes
    }
}

private final class EpisodeParserDelegate: NSObject, XMLParserDelegate {
    var episodes: [PodcastEpisode] = []
    private var inItem = false
    private var currentTitle = ""
    private var currentDate: Date?
    private var currentEnclosureURL: URL?
    private var currentElement = ""

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return f
    }()

    private static let dateFormatterAlt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return f
    }()

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        if elementName == "item" {
            inItem = true
            currentTitle = ""
            currentDate = nil
            currentEnclosureURL = nil
        }
        if inItem && elementName == "enclosure" {
            if let urlString = attributeDict["url"], let url = URL(string: urlString),
               let type = attributeDict["type"], type.hasPrefix("audio/") {
                currentEnclosureURL = url
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inItem else { return }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        switch currentElement {
        case "title":
            currentTitle += trimmed
        case "pubDate":
            if currentDate == nil {
                currentDate = Self.dateFormatter.date(from: trimmed)
                    ?? Self.dateFormatterAlt.date(from: trimmed)
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "item" {
            if let url = currentEnclosureURL, !currentTitle.isEmpty {
                let id = url.absoluteString
                episodes.append(PodcastEpisode(
                    id: id,
                    title: currentTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                    pubDate: currentDate,
                    audioURL: url
                ))
            }
            inItem = false
        }
    }
}
