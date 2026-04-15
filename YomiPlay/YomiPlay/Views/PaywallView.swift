//
//  PaywallView.swift
//  YomiPlay
//
//  订阅墙：SubscriptionStoreView 风格 + 玻璃拟态对比区
//

import SwiftUI
import StoreKit

/// 产品 ID（与 App Store Connect 一致）
private let monthlyProductId = "com.dogiant.yomiplay.monthly"
private let yearlyProductId = "com.dogiant.yomiplay.yearly"
private let lifetimeProductId = "com.dogiant.yomiplay.lifetime"

struct PaywallView: View {
    @Environment(\.locale) private var locale
    var onDismiss: (() -> Void)?
    @State private var products: [Product] = []
    @State private var isLoading = true
    @State private var purchaseError: String?
    @State private var purchasingProductId: String?
    @State private var selectedProductId: String?
    @State private var isRestoring = false
    @State private var restoreMessage: String?
    @State private var showRestoreAlert = false
    private var subscription: SubscriptionManager { SubscriptionManager.shared }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    comparisonGlassSection

                    if !products.isEmpty {
                        productSection
                        unlockButton
                    } else if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 48)
                    } else {
                        Text("paywall_products_unavailable")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    }

                    footerLinks

                    if let err = purchaseError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(paywallBackground)
            .navigationTitle("pro_subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        HapticManager.shared.selection()
                        onDismiss?()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
            .task { await loadProducts() }
            .alert("restore_purchases", isPresented: $showRestoreAlert) {
                Button("ok") {
                    if subscription.isProUser { onDismiss?() }
                }
            } message: {
                Text(restoreMessage ?? "")
            }
        }
    }

    /// 页面背景：轻微渐变，衬托玻璃拟态
    private var paywallBackground: some View {
        LinearGradient(
            colors: [
                Color(.systemGroupedBackground),
                Color(.systemGroupedBackground).opacity(0.98),
                Color(.secondarySystemGroupedBackground).opacity(0.6)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - 对比区：Card 布局，Pro 列淡金/紫渐变 + 发光边框

    private static let proGradient = LinearGradient(
        colors: [
            Color.yellow.opacity(0.12),
            Color.orange.opacity(0.08),
            Color.purple.opacity(0.06)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private static let crownGradient = LinearGradient(
        colors: [Color.yellow, Color.orange],
        startPoint: .top,
        endPoint: .bottom
    )

    private static let proGlowGradient = LinearGradient(
        colors: [
            Color.yellow.opacity(0.4),
            Color.orange.opacity(0.25),
            Color.purple.opacity(0.2)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - 玻璃拟态对比区（VStack 自定义卡片，Pro 文案更亮/金色）

    private static let proTextColor = Color(red: 0.72, green: 0.52, blue: 0.04) // 暖金

    private var comparisonGlassSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("free_vs_pro")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)

            VStack(spacing: 8) {
                compactBenefitRow(
                    icon: "clock.fill",
                    title: "quota_per_month",
                    free: String(
                        format: String(
                            localized: LocalizedStringResource("paywall_free_quota_compact", locale: locale)
                        ),
                        subscription.monthlyUsedSeconds / 60,
                        subscription.remainingFreeSeconds / 60
                    ),
                    pro: String(localized: LocalizedStringResource("paywall_pro_quota_compact", locale: locale))
                )
                compactBenefitRow(
                    icon: "waveform",
                    title: "import_type",
                    free: String(localized: LocalizedStringResource("paywall_free_import_compact", locale: locale)),
                    pro: String(localized: LocalizedStringResource("paywall_pro_import_compact", locale: locale))
                )
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.45), .white.opacity(0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
    }

    private func compactBenefitRow(icon: String, title: LocalizedStringKey, free: String, pro: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(format: String(localized: LocalizedStringResource("paywall_tier_free_line", locale: locale)), free))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(String(format: String(localized: LocalizedStringResource("paywall_tier_pro_line", locale: locale)), pro))
                    .font(.caption2)
                    .foregroundStyle(Self.proTextColor)
                    .fontWeight(.medium)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// 每月识别额度：Free 列动态显示当前使用进度（结合 SubscriptionManager）
    private var quotaComparisonCard: some View {
        let usedMin = subscription.monthlyUsedSeconds / 60
        let limitMin = subscription.freeQuotaLimitSeconds / 60
        let remainingMin = subscription.remainingFreeSeconds / 60
        let progress = limitMin > 0 ? Double(subscription.monthlyUsedSeconds) / Double(subscription.freeQuotaLimitSeconds) : 0

        return VStack(alignment: .leading, spacing: 12) {
            Text("quota_per_month")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.fill")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Free")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                    Text(String(format: String(localized: LocalizedStringResource("quota_progress_format", locale: locale)), usedMin, remainingMin))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                    ProgressView(value: min(1, progress))
                        .tint(.orange)
                        .scaleEffect(y: 0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "crown.fill")
                            .font(.subheadline)
                            .foregroundStyle(Self.crownGradient)
                        Text("Pro")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                    }
                    Text("pro_quota_unlimited")
                        .font(.caption)
                        .foregroundStyle(Self.proTextColor)
                        .fontWeight(.medium)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background(Self.proGradient)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Self.proGlowGradient, lineWidth: 1.2)
                )
                .shadow(color: Color.orange.opacity(0.15), radius: 8, x: 0, y: 3)
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func comparisonCard(
        title: LocalizedStringKey,
        freeIcon: String,
        free: LocalizedStringKey,
        pro: LocalizedStringKey
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: freeIcon)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Free")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                    Text(free)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "crown.fill")
                            .font(.subheadline)
                            .foregroundStyle(Self.crownGradient)
                        Text("Pro")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                    }
                    Text(pro)
                        .font(.caption)
                        .foregroundStyle(Self.proTextColor)
                        .fontWeight(.medium)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background(Self.proGradient)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Self.proGlowGradient, lineWidth: 1.2)
                )
                .shadow(color: Color.orange.opacity(0.15), radius: 8, x: 0, y: 3)
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func proOnlyCard(
        title: LocalizedStringKey,
        icon: String,
        pro: LocalizedStringKey
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.subheadline)
                        .foregroundStyle(Self.crownGradient)
                    Text("pro_exclusive")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }
                Text(pro)
                    .font(.caption)
                    .foregroundStyle(Self.proTextColor)
                    .fontWeight(.medium)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(Self.proGradient)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Self.proGlowGradient, lineWidth: 1.2)
            )
            .shadow(color: Color.orange.opacity(0.15), radius: 8, x: 0, y: 3)
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - 页脚：恢复购买 + 服务条款/隐私政策（符合 Apple 规范）

    private var termsURL: URL? {
        switch legalPathLocaleCode {
        case "zh":
            return URL(string: "https://toshiki.tech/zh/yomiplay/terms")
        case "zh-tw":
            return URL(string: "https://toshiki.tech/zh-tw/yomiplay/terms")
        case "ja":
            return URL(string: "https://toshiki.tech/ja/yomiplay/terms")
        default:
            return URL(string: "https://toshiki.tech/en/yomiplay/terms")
        }
    }
    private var privacyURL: URL? {
        switch legalPathLocaleCode {
        case "zh":
            return URL(string: "https://toshiki.tech/zh/yomiplay/privacy")
        case "zh-tw":
            return URL(string: "https://toshiki.tech/zh-tw/yomiplay/privacy")
        case "ja":
            return URL(string: "https://toshiki.tech/ja/yomiplay/privacy")
        default:
            return URL(string: "https://toshiki.tech/en/yomiplay/privacy")
        }
    }

    /// 法务页面路径语言：en / zh / zh-tw / ja（其它默认 en）
    private var legalPathLocaleCode: String {
        let language = locale.language.languageCode?.identifier.lowercased() ?? "en"
        let fullId = locale.identifier.lowercased()
        if language == "zh" {
            if fullId.contains("hant") || fullId.contains("tw") || fullId.contains("hk") || fullId.contains("mo") {
                return "zh-tw"
            }
            return "zh"
        }
        if language == "ja" { return "ja" }
        return "en"
    }

    private var footerLinks: some View {
        VStack(spacing: 16) {
            Button {
                Task { await restorePurchases() }
            } label: {
                if isRestoring {
                    ProgressView()
                        .scaleEffect(0.9)
                } else {
                    Text("restore_purchases")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(isRestoring)
            .frame(minHeight: 44)

            if termsURL != nil || privacyURL != nil {
                HStack(spacing: 8) {
                    if let url = termsURL {
                        Link(destination: url) {
                            Text("paywall_terms")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if termsURL != nil, privacyURL != nil {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    if let url = privacyURL {
                        Link(destination: url) {
                            Text("paywall_privacy")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.top, 20)
    }

    private func restorePurchases() async {
        await MainActor.run { isRestoring = true }
        await subscription.updateSubscriptionStatus()
        await MainActor.run {
            isRestoring = false
            restoreMessage = subscription.isProUser
                ? String(localized: LocalizedStringResource("paywall_restore_success", locale: locale))
                : String(localized: LocalizedStringResource("paywall_restore_no_entitlement", locale: locale))
            showRestoreAlert = true
        }
    }

    // MARK: - 订阅方案区（SubscriptionStoreView 风格）

    private var productSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("choose_plan")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    Task { await restorePurchases() }
                } label: {
                    if isRestoring {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Text("restore_purchases")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(isRestoring)
            }

            VStack(spacing: 10) {
                ForEach(products, id: \.id) { product in
                    priceCard(product)
                }
            }
        }
    }

    private func priceCard(_ product: Product) -> some View {
        let isSelected = selectedProductId == product.id
        let isYearly = product.id == yearlyProductId
        let isLifetime = product.id == lifetimeProductId
        let isPurchasing = purchasingProductId == product.id

        return Button {
            HapticManager.shared.selection()
            selectedProductId = product.id
        } label: {
            ZStack(alignment: .topTrailing) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(localizedPlanName(for: product))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                            if isYearly {
                                Text("paywall_most_popular")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Color.orange))
                            }
                        }
                        subscriptionDetailTexts(for: product, isLifetime: isLifetime, isYearly: isYearly)
                    }
                    Spacer()
                    if isPurchasing {
                        ProgressView()
                            .scaleEffect(0.9)
                    } else {
                        Text(product.displayPrice)
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundStyle(.green)
                    }
                }
                .padding(.horizontal, isYearly ? 20 : 18)
                .padding(.vertical, isYearly ? 18 : 16)
                .background {
                    if isYearly {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.regularMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.orange.opacity(0.12),
                                                Color.orange.opacity(0.04)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.regularMaterial)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: isYearly ? 20 : 18, style: .continuous)
                        .strokeBorder(
                            isYearly ? (isSelected ? Color.orange : Color.orange.opacity(0.4)) : (isSelected ? Color.green : Color.primary.opacity(0.08)),
                            lineWidth: isSelected ? 2.5 : (isYearly ? 1.5 : 1)
                        )
                )
                .shadow(color: isYearly ? Color.orange.opacity(0.15) : .clear, radius: 12, x: 0, y: 4)

                EmptyView()
            }
        }
        .buttonStyle(.plain)
        .disabled(isPurchasing)
    }

    @ViewBuilder
    private func subscriptionDetailTexts(for product: Product, isLifetime: Bool, isYearly: Bool) -> some View {
        if isLifetime {
            Text("paywall_lifetime_tagline")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("paywall_one_time_purchase")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else if let period = product.subscription?.subscriptionPeriod {
            let periodPhrase = localizedSubscriptionPeriod(period)
            Text(String(format: String(localized: LocalizedStringResource("paywall_auto_renews_format", locale: locale)), periodPhrase))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let monthlyLine = formattedMonthlyEquivalent(for: product, isYearly: isYearly) {
                Text(monthlyLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func localizedSubscriptionPeriod(_ period: Product.SubscriptionPeriod) -> String {
        let v = period.value
        switch period.unit {
        case .day:
            if v == 1 {
                return String(localized: LocalizedStringResource("paywall_period_1_day", locale: locale))
            }
            return String(format: String(localized: LocalizedStringResource("paywall_period_n_days", locale: locale)), v)
        case .week:
            if v == 1 {
                return String(localized: LocalizedStringResource("paywall_period_1_week", locale: locale))
            }
            return String(format: String(localized: LocalizedStringResource("paywall_period_n_weeks", locale: locale)), v)
        case .month:
            if v == 1 {
                return String(localized: LocalizedStringResource("paywall_period_1_month", locale: locale))
            }
            return String(format: String(localized: LocalizedStringResource("paywall_period_n_months", locale: locale)), v)
        case .year:
            if v == 1 {
                return String(localized: LocalizedStringResource("paywall_period_1_year", locale: locale))
            }
            return String(format: String(localized: LocalizedStringResource("paywall_period_n_years", locale: locale)), v)
        @unknown default:
            return ""
        }
    }

    private func formattedMonthlyEquivalent(for product: Product, isYearly: Bool) -> String? {
        guard isYearly, product.subscription != nil else { return nil }
        let monthly = product.price / Decimal(12)
        let priceStr = monthly.formatted(product.priceFormatStyle)
        return String(format: String(localized: LocalizedStringResource("paywall_price_per_month_format", locale: locale)), priceStr)
    }

    private func localizedPlanName(for product: Product) -> String {
        switch product.id {
        case monthlyProductId:
            return String(localized: LocalizedStringResource("paywall_plan_monthly", locale: locale))
        case yearlyProductId:
            return String(localized: LocalizedStringResource("paywall_plan_yearly", locale: locale))
        case lifetimeProductId:
            return String(localized: LocalizedStringResource("paywall_plan_lifetime", locale: locale))
        default:
            return product.displayName
        }
    }

    /// 底部 CTA：立即解锁 Pro（SubscriptionStoreView 风格宽体按钮）
    private var unlockButton: some View {
        let productToPurchase = products.first { $0.id == (selectedProductId ?? yearlyProductId) } ?? products.first
        let isPurchasing = productToPurchase.map { purchasingProductId == $0.id } ?? false

        return Button {
            HapticManager.shared.impact(style: .medium)
            guard let product = productToPurchase else { return }
            Task { await purchase(product) }
        } label: {
            Text("paywall_unlock_pro_button")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.green, Color.green.opacity(0.88)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(isPurchasing)
        .padding(.top, 12)
    }

    private func loadProducts() async {
        let ids = [monthlyProductId, yearlyProductId, lifetimeProductId]
        do {
            let list = try await Product.products(for: Set(ids))
            await MainActor.run {
                products = list.sorted { p1, p2 in
                    let order = [monthlyProductId, yearlyProductId, lifetimeProductId]
                    let i1 = order.firstIndex(of: p1.id) ?? 99
                    let i2 = order.firstIndex(of: p2.id) ?? 99
                    return i1 < i2
                }
                if selectedProductId == nil, products.contains(where: { $0.id == yearlyProductId }) {
                    selectedProductId = yearlyProductId
                }
                isLoading = false
            }
        } catch {
            await MainActor.run {
                purchaseError = String(localized: LocalizedStringResource("paywall_store_products_failed", locale: locale))
                isLoading = false
            }
        }
    }

    private func purchase(_ product: Product) async {
        await MainActor.run {
            purchasingProductId = product.id
            purchaseError = nil
        }
        do {
            let result = try await product.purchase()
            await MainActor.run {
                purchasingProductId = nil
                switch result {
                case .success(let verification):
                    switch verification {
                    case .verified:
                        Task { await SubscriptionManager.shared.updateSubscriptionStatus() }
                        onDismiss?()
                    case .unverified:
                        purchaseError = String(localized: LocalizedStringResource("purchase_verification_failed", locale: locale))
                    }
                case .userCancelled:
                    break
                case .pending:
                    purchaseError = String(localized: LocalizedStringResource("purchase_pending", locale: locale))
                @unknown default:
                    break
                }
            }
        } catch {
            await MainActor.run {
                purchasingProductId = nil
                purchaseError = String(localized: LocalizedStringResource("paywall_purchase_failed", locale: locale))
            }
        }
    }
}

#Preview {
    PaywallView(onDismiss: {})
}
