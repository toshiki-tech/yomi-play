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
    /// 解析失败的具体原因。`nil` 表示成功；非 nil 时配合 `isSupported == false` 用于上层显示精准提示。
    let failureReason: RemoteSourceError?
    /// 是否需要先下载再使用
    var requiresDownload: Bool { resolvedAudioURL != nil && sourceKind != .unsupported }
    var isSupported: Bool { sourceKind != .unsupported && resolvedAudioURL != nil }
}

enum RemoteSourceError: LocalizedError, Sendable, Equatable {
    case unsupportedURL
    case cannotResolveAudio
    case invalidFeed
    case blockedSource
    /// 网络不可达（DNS 解析失败 / 连不上主机 / TLS 握手失败 / 链路被切断 / 离线等）
    /// `code` 用于日志与诊断；面向用户文案统一为「链接无法访问」。
    case networkUnreachable(URLError.Code)
    /// 拉取链接超时
    case networkTimeout
    /// RSS feed 拉取失败（HTTP 异常 / 网络异常）
    case feedFetchFailed(URLError.Code)
    /// RSS feed 拉取成功但解析后没有任何可用 audio enclosure
    case feedEmpty

    var errorDescription: String? {
        switch self {
        case .unsupportedURL: return String(localized: "podcast_link_unresolvable")
        case .cannotResolveAudio: return String(localized: "podcast_link_unresolvable")
        case .invalidFeed: return String(localized: "podcast_feed_invalid")
        case .feedEmpty: return String(localized: "podcast_feed_invalid")
        case .blockedSource: return String(localized: "podcast_link_unresolvable")
        case .networkUnreachable: return String(localized: "podcast_link_network_unreachable")
        case .networkTimeout: return String(localized: "podcast_link_network_timeout")
        case .feedFetchFailed: return String(localized: "podcast_link_network_unreachable")
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
    /// - Returns: 解析结果。若 `isSupported == false`，可通过 `failureReason` 拿到精确原因（网络不可达 / 链接不支持 / feed 解析失败等）。
    static func resolve(originalURL: URL) async -> ResolvedRemoteMedia {
        let trimmed = originalURL.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme == "https" || url.scheme == "http" else {
            return unsupported(originalURL, kind: .unsupported, reason: .unsupportedURL)
        }

        let ext = url.pathExtension.lowercased()
        if streamingExtensions.contains(ext) {
            return ResolvedRemoteMedia(
                originalURL: url,
                resolvedAudioURL: nil,
                sourceKind: .unsupported,
                title: nil,
                mimeType: "application/vnd.apple.mpegurl",
                failureReason: .unsupportedURL
            )
        }
        if audioPathExtensions.contains(ext) {
            return ResolvedRemoteMedia(
                originalURL: url,
                resolvedAudioURL: url,
                sourceKind: .directAudio,
                title: url.deletingPathExtension().lastPathComponent,
                mimeType: nil,
                failureReason: nil
            )
        }

        // RSS / XML feed：拉取并解析第一个 enclosure
        if ext == "xml" || ext == "rss" || url.absoluteString.lowercased().contains("feed") || url.absoluteString.lowercased().contains("rss") {
            do {
                if let enclosure = try await firstAudioEnclosure(fromFeed: url) {
                    return ResolvedRemoteMedia(
                        originalURL: url,
                        resolvedAudioURL: enclosure.url,
                        sourceKind: .rssFeed,
                        title: enclosure.title,
                        mimeType: nil,
                        failureReason: nil
                    )
                }
                return unsupported(url, kind: .rssFeed, reason: .feedEmpty)
            } catch let err as RemoteSourceError {
                return unsupported(url, kind: .rssFeed, reason: err)
            } catch {
                return unsupported(url, kind: .rssFeed, reason: .invalidFeed)
            }
        }

        // 播客目录/节目页（如 podcasts.apple.com）：仅作分类，不解析 HTML
        if url.host?.lowercased().contains("podcasts.apple.com") == true || url.host?.lowercased().contains("itunes.apple.com") == true {
            return unsupported(url, kind: .applePodcastPage, reason: .unsupportedURL)
        }

        // 其他：尝试 HEAD 看 Content-Type
        do {
            let (finalURL, contentType) = try await fetchContentType(for: url)
            let lowerCT = contentType.lowercased()
            if lowerCT.hasPrefix("audio/") {
                return ResolvedRemoteMedia(
                    originalURL: url,
                    resolvedAudioURL: finalURL,
                    sourceKind: .directAudio,
                    title: url.deletingPathExtension().lastPathComponent,
                    mimeType: contentType,
                    failureReason: nil
                )
            }
            if lowerCT.contains("rss") || lowerCT.contains("xml") {
                do {
                    if let enclosure = try await firstAudioEnclosure(fromFeed: finalURL) {
                        return ResolvedRemoteMedia(
                            originalURL: url,
                            resolvedAudioURL: enclosure.url,
                            sourceKind: .rssFeed,
                            title: enclosure.title,
                            mimeType: nil,
                            failureReason: nil
                        )
                    }
                    return unsupported(url, kind: .rssFeed, reason: .feedEmpty)
                } catch let err as RemoteSourceError {
                    return unsupported(url, kind: .rssFeed, reason: err)
                } catch {
                    return unsupported(url, kind: .rssFeed, reason: .invalidFeed)
                }
            }
            if lowerCT.contains("html") {
                return ResolvedRemoteMedia(
                    originalURL: url,
                    resolvedAudioURL: nil,
                    sourceKind: .webpage,
                    title: nil,
                    mimeType: contentType,
                    failureReason: .unsupportedURL
                )
            }
            return unsupported(url, kind: .unsupported, reason: .cannotResolveAudio)
        } catch let err as RemoteSourceError {
            return unsupported(url, kind: .unsupported, reason: err)
        } catch {
            return unsupported(url, kind: .unsupported, reason: .cannotResolveAudio)
        }
    }

    private static func unsupported(_ url: URL, kind: RemoteSourceKind, reason: RemoteSourceError) -> ResolvedRemoteMedia {
        ResolvedRemoteMedia(
            originalURL: url,
            resolvedAudioURL: nil,
            sourceKind: kind,
            title: nil,
            mimeType: nil,
            failureReason: reason
        )
    }

    /// HEAD 请求拿 Content-Type。网络异常时把 `URLError` 映射为 `RemoteSourceError` 抛出，便于上层精准归类。
    private static func fetchContentType(for url: URL) async throws -> (URL, String) {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.setValue(RemoteAudioFetcher.compatibilityUserAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        let response: URLResponse
        do {
            (_, response) = try await URLSession.shared.data(for: request)
        } catch let err as URLError {
            throw mapURLError(err)
        }
        guard let http = response as? HTTPURLResponse else {
            throw RemoteSourceError.cannotResolveAudio
        }
        guard (200...299).contains(http.statusCode) else {
            // 4xx/5xx：链接看似可达但服务端拒绝，归到 `cannotResolveAudio`，由上层显示「无法解析」文案
            throw RemoteSourceError.cannotResolveAudio
        }
        guard let ct = http.value(forHTTPHeaderField: "Content-Type")?
            .split(separator: ";").first.map(String.init) else {
            throw RemoteSourceError.cannotResolveAudio
        }
        return (url, ct)
    }

    /// 拉取并解析 RSS feed 的第一个 audio enclosure。网络异常 → `feedFetchFailed`；解析空 → 返回 nil；解析异常 → `invalidFeed`。
    private static func firstAudioEnclosure(fromFeed feedURL: URL) async throws -> (url: URL, title: String?)? {
        var request = URLRequest(url: feedURL)
        request.setValue(RemoteAudioFetcher.compatibilityUserAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30
        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch let err as URLError {
            // RSS feed 的网络问题用专门的 case，便于和"链接本身不支持"区分
            if err.code == .timedOut {
                throw RemoteSourceError.networkTimeout
            }
            throw RemoteSourceError.feedFetchFailed(err.code)
        }
        guard !data.isEmpty else { return nil }
        let delegate = FirstEnclosureParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.firstEnclosure
    }

    /// 把 URLError 归类成 `RemoteSourceError`，集中给国内常见网络故障的命名
    private static func mapURLError(_ err: URLError) -> RemoteSourceError {
        switch err.code {
        case .timedOut:
            return .networkTimeout
        case .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .secureConnectionFailed,
             .serverCertificateUntrusted,
             .serverCertificateHasBadDate,
             .serverCertificateNotYetValid,
             .clientCertificateRejected,
             .networkConnectionLost,
             .notConnectedToInternet,
             .cannotLoadFromNetwork,
             .internationalRoamingOff,
             .dataNotAllowed:
            return .networkUnreachable(err.code)
        default:
            return .networkUnreachable(err.code)
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
