//
//  RemoteAudioFetcher.swift
//  YomiPlay
//
//  仅负责将“已解析出的远程音频地址”下载到本地。
//  使用常见播客客户端风格的请求头作为兼容手段，提高部分公开源成功率；
//  不表示“官方播客下载”能力，不保证所有源均可下载。
//

import Foundation

/// 下载层错误（便于上层区分并给出准确提示）
enum DownloadError: LocalizedError, Sendable {
    case restricted              // 403
    case notFound                // 404
    case unauthorized            // 401
    case rateLimited             // 429
    case timeout
    case invalidResponse
    case invalidContentType
    case unsupportedFormat
    case streamingOnlySource
    case fileTooLarge
    case insufficientStorage
    case networkUnavailable
    case downloadFailed(reason: String?)

    var errorDescription: String? {
        switch self {
        case .restricted: return String(localized: "podcast_download_restricted")
        case .notFound: return String(localized: "podcast_download_not_found")
        case .unauthorized: return String(localized: "podcast_download_restricted")
        case .rateLimited: return String(localized: "podcast_download_timeout")
        case .timeout: return String(localized: "podcast_download_timeout")
        case .invalidResponse: return String(localized: "failed_to_download_audio")
        case .invalidContentType: return String(localized: "podcast_invalid_content_type")
        case .unsupportedFormat: return String(localized: "podcast_streaming_not_supported")
        case .streamingOnlySource: return String(localized: "podcast_streaming_not_supported")
        case .fileTooLarge: return String(localized: "podcast_file_too_large")
        case .insufficientStorage: return String(localized: "failed_to_download_audio")
        case .networkUnavailable: return String(localized: "failed_to_download_audio")
        case .downloadFailed(let reason): return reason ?? String(localized: "failed_to_download_audio")
        }
    }
}

/// 最大允许下载大小（约 500MB）
private let maxDownloadBytes: Int64 = 500 * 1024 * 1024

/// 非音频 Content-Type 前缀（若响应为此类，直接报错）
private let nonAudioContentTypes = ["text/html", "text/plain", "application/json", "application/javascript", "application/xml"]

/// HLS / 流媒体
private let streamingContentTypes = ["application/vnd.apple.mpegurl", "application/x-mpegurl"]

enum RemoteAudioFetcher {

    /// 兼容部分公开播客源的请求头（仅作兼容手段，不对外宣传）
    static let compatibilityUserAgent = "YomiPlay/1.0 (iOS; language learning)"

    /// 将已解析的远程音频 URL 下载到本地临时文件。
    /// - Parameter url: 解析得到的可直接请求的音频地址
    /// - Returns: 本地临时文件 URL，调用方负责在识别后清理
    static func download(url: URL) async throws -> URL {
        var request = URLRequest(url: url)
        request.setValue(compatibilityUserAgent, forHTTPHeaderField: "User-Agent")
        if let host = url.host {
            request.setValue("https://\(host)/", forHTTPHeaderField: "Referer")
        }
        request.timeoutInterval = 60

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let err as URLError where err.code == .timedOut {
            throw DownloadError.timeout
        } catch let err as URLError where err.code == .notConnectedToInternet || err.code == .networkConnectionLost {
            throw DownloadError.networkUnavailable
        } catch {
            throw DownloadError.downloadFailed(reason: error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw DownloadError.invalidResponse
        }

        switch http.statusCode {
        case 200...299: break
        case 401: throw DownloadError.unauthorized
        case 403: throw DownloadError.restricted
        case 404: throw DownloadError.notFound
        case 429: throw DownloadError.rateLimited
        default: throw DownloadError.downloadFailed(reason: "HTTP \(http.statusCode)")
        }

        let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "")
            .split(separator: ";").first.map(String.init)?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""

        for nonAudio in nonAudioContentTypes {
            if contentType.hasPrefix(nonAudio) {
                throw DownloadError.invalidContentType
            }
        }
        for streaming in streamingContentTypes {
            if contentType.contains(streaming) {
                throw DownloadError.streamingOnlySource
            }
        }

        if data.isEmpty {
            throw DownloadError.invalidResponse
        }
        if Int64(data.count) > maxDownloadBytes {
            throw DownloadError.fileTooLarge
        }

        let ext = url.pathExtension.lowercased()
        let safeExt = audioPathExtensions.contains(ext) ? ext : "mp3"
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + safeExt)
        do {
            try data.write(to: dest)
        } catch {
            throw DownloadError.insufficientStorage
        }
        return dest
    }

    private static let audioPathExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "ogg", "flac", "opus", "weba"]
}
