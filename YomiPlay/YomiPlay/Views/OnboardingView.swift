//
//  OnboardingView.swift
//  YomiPlay
//
//  首次启动时的引导页：简要说明用途 + 学习用途免责声明
//

import SwiftUI

struct OnboardingView: View {
    /// 与 YomiPlayApp.environment(\\.\locale) 一致：默认「跟随系统」= 手机语言；用户在设置里改过界面语言后则跟随应用配置
    @Environment(\.locale) private var locale
    let onContinue: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                // 顶部图标与标题
                VStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(Color.accentColor.opacity(0.1))
                            .frame(width: 110, height: 64)
                        HStack(spacing: 8) {
                            Image(systemName: "books.vertical.fill")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                            Image(systemName: "waveform.circle.fill")
                                .font(.system(size: 26, weight: .regular))
                                .foregroundStyle(.linearGradient(colors: [.green, .green.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                    }

                    VStack(spacing: 6) {
                        Text("YomiPlay")
                            .font(.title)
                            .fontWeight(.bold)

                        Text(String(localized: LocalizedStringResource("onboarding_tagline", locale: locale)))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                // 功能简要说明（多语言）
                VStack(alignment: .leading, spacing: 10) {
                    Text(String(localized: LocalizedStringResource("onboarding_intro_title", locale: locale)))
                        .font(.headline)
                    Text(String(localized: LocalizedStringResource("onboarding_intro_body", locale: locale)))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)

                // 学习用途 / 版权免责声明
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: LocalizedStringResource("onboarding_disclaimer_title", locale: locale)))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(String(localized: LocalizedStringResource("onboarding_disclaimer_body", locale: locale)))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
                .padding(.horizontal, 24)

                Spacer()

                Button(action: onContinue) {
                    Text(String(localized: LocalizedStringResource("onboarding_continue", locale: locale)))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
