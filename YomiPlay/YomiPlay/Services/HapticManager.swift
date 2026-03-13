//
//  HapticManager.swift
//  YomiPlay
//

import UIKit

/// 触覚フィードバックを管理するシングルトンクラス
final class HapticManager {
    static let shared = HapticManager()
    
    private init() {}
    
    /// 成功時の振動
    func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
    
    /// 警告時の振動
    func warning() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }
    
    /// 失敗時の振動
    func error() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
    }
    
    /// 軽い衝撃（ボタンタップ等）
    func impact(style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
    
    /// 選択が変更された時の振動
    func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }
}
