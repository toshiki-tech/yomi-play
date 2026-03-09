//
//  FuriganaTextView.swift
//  YomiPlay
//
//  振り仮名 + ローマ字表示コンポーネント
//  漢字の上に読み、下にローマ字を表示する
//  FlowLayout で自動折り返し対応
//

import SwiftUI

// MARK: - 振り仮名テキストビュー

struct FuriganaTextView: View {
    let tokens: [FuriganaToken]
    let showFurigana: Bool
    let showRomaji: Bool
    let showEnglish: Bool
    let fontSize: CGFloat
    
    init(
        tokens: [FuriganaToken],
        showFurigana: Bool = true,
        showRomaji: Bool = true,
        showEnglish: Bool = false,
        fontSize: CGFloat = 18
    ) {
        self.tokens = tokens
        self.showFurigana = showFurigana
        self.showRomaji = showRomaji
        self.showEnglish = showEnglish
        self.fontSize = fontSize
    }
    
    var body: some View {
        // FlowLayout で折り返し表示
        FlowLayout(spacing: 0) {
            ForEach(tokens) { token in
                TokenView(
                    token: token,
                    showFurigana: showFurigana,
                    showRomaji: showRomaji,
                    showEnglish: showEnglish,
                    fontSize: fontSize
                )
            }
        }
    }
}

// MARK: - FlowLayout（折り返しレイアウト）

/// 子ビューを水平に並べ、幅を超えたら自動的に折り返すレイアウト
struct FlowLayout: Layout {
    var spacing: CGFloat = 0
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            guard index < subviews.count else { break }
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }
    
    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            if currentX + size.width > maxWidth && currentX > 0 {
                // 次の行へ
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            
            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            totalWidth = max(totalWidth, currentX)
        }
        
        return (
            size: CGSize(width: totalWidth, height: currentY + lineHeight),
            positions: positions
        )
    }
}

// MARK: - 個別トークンビュー

struct TokenView: View {
    let token: FuriganaToken
    let showFurigana: Bool
    let showRomaji: Bool
    let showEnglish: Bool
    let fontSize: CGFloat
    
    private var readingFontSize: CGFloat { fontSize * 0.45 }
    private var romajiFontSize: CGFloat { fontSize * 0.4 }
    
    var body: some View {
        VStack(spacing: 0) {
            // 上段：振り仮名 or 英語原綴り
            if showFurigana || showEnglish {
                if showEnglish,
                   token.isKatakana,
                   let meaning = token.englishMeaning,
                   !meaning.isEmpty {
                    Text(meaning)
                        .font(.system(size: readingFontSize))
                        .foregroundStyle(Color.blue.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                } else if showFurigana && token.isKanji {
                    Text(token.reading)
                        .font(.system(size: readingFontSize))
                        .foregroundStyle(Color.green.opacity(0.8))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                } else {
                    Text(" ")
                        .font(.system(size: readingFontSize))
                        .foregroundStyle(.clear)
                }
            }
            
            // 中段：原文
            Text(token.surface)
                .font(.system(size: fontSize, weight: .medium))
            
            // 下段：ローマ字
            if showRomaji {
                let romaji = !token.romaji.isEmpty ? token.romaji : token.surface
                Text(romaji)
                    .font(.system(size: romajiFontSize))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
    }
}

// MARK: - プレビュー

#Preview {
    let sampleTokens: [FuriganaToken] = [
        FuriganaToken(surface: "今日", reading: "きょう", romaji: "kyou", isKanji: true),
        FuriganaToken(surface: "は", romaji: "wa"),
        FuriganaToken(surface: "日本語", reading: "にほんご", romaji: "nihongo", isKanji: true),
        FuriganaToken(surface: "の", romaji: "no"),
        FuriganaToken(surface: "勉強", reading: "べんきょう", romaji: "benkyou", isKanji: true),
        FuriganaToken(surface: "について", romaji: "nitsuite"),
        FuriganaToken(surface: "話", reading: "はな", romaji: "hana", isKanji: true),
        FuriganaToken(surface: "しましょう。", romaji: "shimashou."),
    ]
    
    VStack(spacing: 20) {
        FuriganaTextView(tokens: sampleTokens, showFurigana: true, showRomaji: true, fontSize: 20)
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
    }
    .padding()
    .background(Color.black)
    .preferredColorScheme(.dark)
}
