//
//  OnboardingView.swift
//  YomiPlay
//
//  首次启动时的引导页：简要说明用途 + 学习用途免责声明
//

import SwiftUI

struct OnboardingView: View {
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

                        Group {
                            switch locale.identifier {
                            case let id where id.hasPrefix("zh"):
                                Text("✨ 生成你的学习内容")
                            case let id where id.hasPrefix("ja"):
                                Text("自分だけの学習素材を作る")
                            default:
                                Text("Create Your Learning Content")
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }

                // 功能简要说明（多语言）
                VStack(alignment: .leading, spacing: 10) {
                    Text(onboardingIntroTitle)
                        .font(.headline)
                    Text(onboardingIntroBody)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)

                // 学习用途 / 版权免责声明
                VStack(alignment: .leading, spacing: 8) {
                    Text(onboardingDisclaimerTitle)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(onboardingDisclaimerBody)
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
                    Text(onboardingContinueLabel)
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

    private var onboardingIntroTitle: String {
        switch locale.identifier {
        case let id where id.hasPrefix("zh"):
            return "这是什么应用？"
        case let id where id.hasPrefix("ja"):
            return "このアプリについて"
        default:
            return "What is this app?"
        }
    }

    private var onboardingIntroBody: String {
        switch locale.identifier {
        case let id where id.hasPrefix("zh"):
            return "YomiPlay 使用本地 AI 语音识别，将音频 / 视频生成可学习的字幕，辅助影子跟读和多语言听力练习。你可以导入音视频文件、播客或 ZIP 学习资料。"
        case let id where id.hasPrefix("ja"):
            return "YomiPlay はローカルの AI 音声認識を使って、音声・動画から学習用の字幕を生成し、シャドーイングや多言語リスニングをサポートするアプリです。音声／動画ファイルやポッドキャスト、ZIP 学習素材をインポートできます。"
        default:
            return "YomiPlay uses on‑device AI speech recognition to turn audio / video into study‑friendly subtitles, helping with shadowing and multilingual listening practice. You can import media files, podcasts, or ZIP study bundles."
        }
    }

    private var onboardingDisclaimerTitle: String {
        switch locale.identifier {
        case let id where id.hasPrefix("zh"):
            return "仅供个人学习使用"
        case let id where id.hasPrefix("ja"):
            return "個人学習用途のみ"
        default:
            return "For personal learning use only"
        }
    }

    private var onboardingDisclaimerBody: String {
        switch locale.identifier {
        case let id where id.hasPrefix("zh"):
            return "本应用仅作为个人语言学习工具使用。请确保你导入或下载的音视频、字幕等内容拥有合法使用权限，或仅在合理使用范围内自用学习。对于因导入、分享受版权保护内容而产生的法律责任，由用户本人承担。"
        case let id where id.hasPrefix("ja"):
            return "本アプリは個人の語学学習を目的としたツールです。インポート／ダウンロードする音声・動画・字幕などのコンテンツについては、必ず合法な利用権限を確認し、私的学習の範囲に留めてご利用ください。著作権保護されたコンテンツの利用・共有に伴う責任は、利用者ご自身に帰属します。"
        default:
            return "This app is intended for personal language learning only. Please ensure you have the legal right to use any audio, video, or subtitle content you import or download, and keep your usage within fair use / personal study scope. You are solely responsible for any copyright or legal issues arising from the content you use or share."
        }
    }

    private var onboardingContinueLabel: String {
        switch locale.identifier {
        case let id where id.hasPrefix("zh"):
            return "我已了解，开始使用"
        case let id where id.hasPrefix("ja"):
            return "理解しました。はじめる"
        default:
            return "I understand, start using YomiPlay"
        }
    }
}

