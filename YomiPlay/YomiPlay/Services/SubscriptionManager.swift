//
//  SubscriptionManager.swift
//  YomiPlay
//
//  商业化权限与配额：StoreKit 2 订阅状态 + 免费用户月度识别时长
//

import Foundation
import StoreKit
import AVFoundation

/// 月度免费识别额度（秒）
private let freeQuotaLimit: Int = 1800  // 30 分钟

private let monthlyUsedSecondsKey = "subscription_monthlyUsedSeconds"
private let lastQuotaResetDateKey = "subscription_lastQuotaResetDate"

@Observable
final class SubscriptionManager {
    static let shared = SubscriptionManager()

    #if DEBUG
    /// 设为 true 可模拟 Pro 用户，用于本地测试 Pro 界面（仅 Debug 生效，在设置页可切换）
    var debugSimulateProUser: Bool = false
    #endif

    private var _isProUser: Bool = false
    /// 是否持有有效 Pro 订阅（月付 / 年付 / 终身）；Debug 下受 debugSimulateProUser 影响
    var isProUser: Bool {
        #if DEBUG
        if debugSimulateProUser { return true }
        #endif
        return _isProUser
    }

    private var _proExpirationDate: Date?
    /// Pro 订阅到期日（终身为 nil，用于设置页展示）；Debug 模拟时返回 nil 表示终身
    var proExpirationDate: Date? {
        #if DEBUG
        if debugSimulateProUser { return nil }
        #endif
        return _proExpirationDate
    }

    /// 本月已使用的识别秒数（仅免费用户统计）
    private(set) var monthlyUsedSeconds: Int = 0

    /// 上次重置配额对应的月份（用于跨月自动清零）
    private(set) var lastQuotaResetDate: Date?

    /// 免费额度上限（秒）
    var freeQuotaLimitSeconds: Int { freeQuotaLimit }

    /// 剩余免费额度（秒），Pro 用户返回上限值
    var remainingFreeSeconds: Int {
        if isProUser { return freeQuotaLimit }
        return max(0, freeQuotaLimit - monthlyUsedSeconds)
    }

    private var updates: Task<Void, Never>?

    init() {
        loadQuotaFromStorage()
        updates = Task { await observeTransactions() }
        Task { await updateSubscriptionStatus() }
    }

    deinit {
        updates?.cancel()
    }

    // MARK: - StoreKit 2 订阅状态

    private static let productIds: Set<String> = [
        "com.dogiant.yomimark.monthly",
        "com.dogiant.yomimark.yearly",
        "com.dogiant.yomimark.lifetime"
    ]

    func updateSubscriptionStatus() async {
        var hasValidEntitlement = false
        var latestExpiration: Date?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let tx) = result else { continue }
            if Self.productIds.contains(tx.productID) {
                if tx.productID == "com.dogiant.yomimark.lifetime" {
                    hasValidEntitlement = true
                    latestExpiration = nil
                    break
                }
                if let expiration = tx.expirationDate, expiration > Date() {
                    hasValidEntitlement = true
                    if latestExpiration == nil || expiration > latestExpiration! {
                        latestExpiration = expiration
                    }
                }
            }
        }
        await MainActor.run {
            _isProUser = hasValidEntitlement
            _proExpirationDate = latestExpiration
        }
    }

    private func observeTransactions() async {
        for await result in Transaction.updates {
            guard case .verified(_) = result else { continue }
            await updateSubscriptionStatus()
        }
    }

    // MARK: - 配额（UserDefaults）

    private func loadQuotaFromStorage() {
        let ud = UserDefaults.standard
        monthlyUsedSeconds = ud.integer(forKey: monthlyUsedSecondsKey)
        lastQuotaResetDate = ud.object(forKey: lastQuotaResetDateKey) as? Date
        resetQuotaIfNeeded()
    }

    /// 若当前月份与上次记录不同，将本月已用秒数清零
    func resetQuotaIfNeeded() {
        let calendar = Calendar.current
        let now = Date()
        let currentMonth = calendar.component(.month, from: now)
        let currentYear = calendar.component(.year, from: now)

        if let last = lastQuotaResetDate {
            let lastMonth = calendar.component(.month, from: last)
            let lastYear = calendar.component(.year, from: last)
            if currentYear != lastYear || currentMonth != lastMonth {
                monthlyUsedSeconds = 0
                lastQuotaResetDate = now
                UserDefaults.standard.set(0, forKey: monthlyUsedSecondsKey)
                UserDefaults.standard.set(now, forKey: lastQuotaResetDateKey)
                return
            }
        }
        if lastQuotaResetDate == nil {
            lastQuotaResetDate = now
            UserDefaults.standard.set(now, forKey: lastQuotaResetDateKey)
        }
    }

    /// 增加本月已用识别秒数（仅免费用户；识别完成后调用）
    func addUsedSeconds(_ seconds: Int) {
        guard !isProUser, seconds > 0 else { return }
        resetQuotaIfNeeded()
        monthlyUsedSeconds += seconds
        UserDefaults.standard.set(monthlyUsedSeconds, forKey: monthlyUsedSecondsKey)
    }

    /// 免费用户：当前已用 + 本次时长 是否超过 30 分钟
    func canUseRecognitionSeconds(_ additionalSeconds: Int) -> Bool {
        if isProUser { return true }
        resetQuotaIfNeeded()
        return (monthlyUsedSeconds + additionalSeconds) <= freeQuotaLimit
    }

    /// 获取给定 URL 的媒体时长（秒），用于配额预检
    static func durationSeconds(of url: URL) async -> Int {
        let asset = AVURLAsset(url: url)
        do {
            let cmDuration = try await asset.load(.duration)
            let sec = CMTimeGetSeconds(cmDuration)
            return Int(ceil(max(0, sec)))
        } catch {
            return 0
        }
    }
}
