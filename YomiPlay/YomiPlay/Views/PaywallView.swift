//
//  PaywallView.swift
//  YomiPlay
//
//  订阅墙：SubscriptionStoreView 风格 + 玻璃拟态对比区
//

import SwiftUI
import StoreKit

/// 产品 ID（与 App Store Connect 一致）
private let monthlyProductId = "com.dogiant.yomimark.monthly"
private let yearlyProductId = "com.dogiant.yomimark.yearly"
private let lifetimeProductId = "com.dogiant.yomimark.lifetime"

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
                VStack(spacing: 28) {
                    comparisonGlassSection

                    if !products.isEmpty {
                        productSection
                        unlockButton
                        footerLinks
                    } else if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 48)
                    }

                    if let err = purchaseError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
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
        VStack(alignment: .leading, spacing: 20) {
            Text("free_vs_pro")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)

            VStack(spacing: 14) {
                quotaComparisonCard
                comparisonCard(
                    title: "import_type",
                    freeIcon: "waveform",
                    free: "free_audio_only",
                    pro: "pro_video_supported"
                )
                proOnlyCard(
                    title: "export_share",
                    icon: "square.and.arrow.up",
                    pro: "pro_export_srt_yomi_media"
                )
                proOnlyCard(
                    title: "zip_export",
                    icon: "doc.zipper",
                    pro: "pro_zip_export"
                )
            }
        }
        .padding(22)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.45), .white.opacity(0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 8)
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

    /// 替换为实际 URL 或设为 nil 隐藏链接
    private static let termsURL: URL? = URL(string: "https://example.com/terms")
    private static let privacyURL: URL? = URL(string: "https://example.com/privacy")

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

            if Self.termsURL != nil || Self.privacyURL != nil {
                HStack(spacing: 8) {
                    if let url = Self.termsURL {
                        Link(destination: url) {
                            Text("paywall_terms")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if Self.termsURL != nil, Self.privacyURL != nil {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    if let url = Self.privacyURL {
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
                ? String(localized: "paywall_restore_success")
                : String(localized: "paywall_restore_no_entitlement")
            showRestoreAlert = true
        }
    }

    // MARK: - 订阅方案区（SubscriptionStoreView 风格）

    private var productSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("choose_plan")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)

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
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(product.displayName)
                            .font(isYearly ? .subheadline : .subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        if isLifetime {
                            Text("paywall_lifetime_tagline")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(product.description)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
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

                if isYearly {
                    Text("paywall_most_popular")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.orange))
                        .padding(14)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isPurchasing)
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
                purchaseError = error.localizedDescription
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
                        purchaseError = String(localized: "purchase_verification_failed")
                    }
                case .userCancelled:
                    break
                case .pending:
                    purchaseError = String(localized: "purchase_pending")
                @unknown default:
                    break
                }
            }
        } catch {
            await MainActor.run {
                purchasingProductId = nil
                purchaseError = error.localizedDescription
            }
        }
    }
}

#Preview {
    PaywallView(onDismiss: {})
}
