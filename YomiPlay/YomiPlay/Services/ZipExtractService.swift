//
//  ZipExtractService.swift
//  YomiPlay
//
//  ZIP 解凍：Documents/Imports/<name>/ に展開する
//

import Foundation
import Compression

enum ZipExtractService {
    
    private static let localHeaderSignature: UInt32 = 0x04034b50
    private static let centralHeaderSignature: UInt32 = 0x02014b50
    private static let endOfCentralSignature: UInt32 = 0x06054b50
    
    /// ZIP を解凍し、展開先ディレクトリの URL を返す。失敗時は nil
    static func extract(zipURL: URL, destinationParent: URL, folderName: String) throws -> URL {
        let hasAccess = zipURL.startAccessingSecurityScopedResource()
        defer { if hasAccess { zipURL.stopAccessingSecurityScopedResource() } }
        
        let data = try Data(contentsOf: zipURL)
        let destDir = destinationParent
            .appendingPathComponent("Imports", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
        
        if FileManager.default.fileExists(atPath: destDir.path) {
            try FileManager.default.removeItem(at: destDir)
        }
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        
        let entries = try readCentralDirectory(data: data)
        for entry in entries where !entry.isDirectory {
            try extractEntry(entry, from: data, to: destDir)
        }
        return destDir
    }
    
    private struct ZipEntry {
        let fileName: String
        let compressionMethod: UInt16
        let localHeaderOffset: Int
        let compressedSize: Int
        let uncompressedSize: Int
        var isDirectory: Bool { fileName.hasSuffix("/") }
    }
    
    private static func findEndOfCentralDirectory(in data: Data) -> (offset: Int, cdOffset: Int, cdSize: Int, totalEntries: Int)? {
        let sig = [0x50 as UInt8, 0x4b, 0x05, 0x06]
        let searchStart = max(0, data.count - 65557)
        var eocdOffset = -1
        for i in (searchStart..<(data.count - 4)).reversed() {
            if data[i] == sig[0], data[i+1] == sig[1], data[i+2] == sig[2], data[i+3] == sig[3] {
                eocdOffset = i
                break
            }
        }
        guard eocdOffset >= 0, eocdOffset + 22 <= data.count else { return nil }
        
        let totalEntries = Int(data[eocdOffset + 8]) | (Int(data[eocdOffset + 9]) << 8)
        let cdSize = Int(data[eocdOffset + 12]) | (Int(data[eocdOffset + 13]) << 8) | (Int(data[eocdOffset + 14]) << 16) | (Int(data[eocdOffset + 15]) << 24)
        let cdOffset = Int(data[eocdOffset + 16]) | (Int(data[eocdOffset + 17]) << 8) | (Int(data[eocdOffset + 18]) << 16) | (Int(data[eocdOffset + 19]) << 24)
        return (eocdOffset, cdOffset, cdSize, totalEntries)
    }
    
    private static func readCentralDirectory(data: Data) throws -> [ZipEntry] {
        guard let (_, cdOffset, cdSize, totalEntries) = findEndOfCentralDirectory(in: data) else {
            throw NSError(domain: "ZipExtract", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid ZIP: EOCD not found"])
        }
        var entries: [ZipEntry] = []
        var offset = cdOffset
        let end = cdOffset + cdSize
        
        for _ in 0..<totalEntries {
            guard offset + 46 <= data.count, offset < end else { break }
            let sig = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self) }
            guard sig == centralHeaderSignature else { break }
            
            let compressionMethod = UInt16(data[offset + 10]) | (UInt16(data[offset + 11]) << 8)
            let compressedSize = Int(data[offset + 20]) | (Int(data[offset + 21]) << 8) | (Int(data[offset + 22]) << 16) | (Int(data[offset + 23]) << 24)
            let uncompressedSize = Int(data[offset + 24]) | (Int(data[offset + 25]) << 8) | (Int(data[offset + 26]) << 16) | (Int(data[offset + 27]) << 24)
            let fileNameLength = Int(data[offset + 28]) | (Int(data[offset + 29]) << 8)
            let extraLength = Int(data[offset + 30]) | (Int(data[offset + 31]) << 8)
            let commentLength = Int(data[offset + 32]) | (Int(data[offset + 33]) << 8)
            let localHeaderOffset = Int(data[offset + 42]) | (Int(data[offset + 43]) << 8) | (Int(data[offset + 44]) << 16) | (Int(data[offset + 45]) << 24)
            
            let nameStart = offset + 46
            let nameEnd = nameStart + fileNameLength
            guard nameEnd <= data.count else { break }
            let nameData = data.subdata(in: nameStart..<nameEnd)
            guard let fileName = String(data: nameData, encoding: .utf8) else {
                offset += 46 + fileNameLength + extraLength + commentLength
                continue
            }
            
            entries.append(ZipEntry(
                fileName: fileName,
                compressionMethod: compressionMethod,
                localHeaderOffset: localHeaderOffset,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize
            ))
            offset += 46 + fileNameLength + extraLength + commentLength
        }
        return entries
    }
    
    private static func extractEntry(_ entry: ZipEntry, from data: Data, to destDir: URL) throws {
        let localOffset = entry.localHeaderOffset
        guard localOffset + 30 <= data.count else { return }
        let sig = data.withUnsafeBytes { $0.load(fromByteOffset: localOffset, as: UInt32.self) }
        guard sig == localHeaderSignature else { return }
        
        let fileNameLength = Int(data[localOffset + 26]) | (Int(data[localOffset + 27]) << 8)
        let extraLength = Int(data[localOffset + 28]) | (Int(data[localOffset + 29]) << 8)
        let payloadStart = localOffset + 30 + fileNameLength + extraLength
        let payloadEnd = payloadStart + entry.compressedSize
        guard payloadEnd <= data.count else { return }
        
        let payload = data.subdata(in: payloadStart..<payloadEnd)
        let outData: Data
        switch entry.compressionMethod {
        case 0: // stored
            outData = payload
        case 8: // deflate
            outData = try decompressDeflate(payload, expectedLength: entry.uncompressedSize)
        default:
            return
        }
        
        var safeName = (entry.fileName as NSString).lastPathComponent
        if safeName.isEmpty { safeName = "file_\(entry.localHeaderOffset)" }
        let destURL = destDir.appendingPathComponent(safeName)
        if let dir = destURL.deletingLastPathComponent() as URL?, dir != destDir {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try outData.write(to: destURL)
    }
    
    /// ZIP は raw deflate。zlib ヘッダ (0x78 0x9C) を付けて COMPRESSION_ZLIB で復号する
    private static func decompressDeflate(_ data: Data, expectedLength: Int) throws -> Data {
        let zlibHeader = Data([0x78, 0x9C])
        let zlibData = zlibHeader + data
        let capacity = max(expectedLength * 2, 64 * 1024)
        let destBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { destBuffer.deallocate() }
        
        let decodedCount = zlibData.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> Int in
            guard let base = ptr.baseAddress else { return 0 }
            return compression_decode_buffer(
                destBuffer,
                capacity,
                base.assumingMemoryBound(to: UInt8.self),
                ptr.count,
                nil,
                COMPRESSION_ZLIB
            )
        }
        guard decodedCount > 0 else {
            throw NSError(domain: "ZipExtract", code: -2, userInfo: [NSLocalizedDescriptionKey: "Decompression failed"])
        }
        return Data(bytes: destBuffer, count: decodedCount)
    }
}
