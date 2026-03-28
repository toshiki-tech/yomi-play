//
//  ShadowReadingPracticeSheet.swift
//  YomiPlay
//
//  跟读本句：录音 → 本地 Whisper 转写 → 与原文文本相似度（B 档轻量，非发音评测）
//

import SwiftUI

struct ShadowReadingPracticeSheet: View {
    let segment: TranscriptSegment
    let locale: Locale
    let onDismiss: () -> Void
    let onPausePlayback: () -> Void

    private enum Phase {
        case idle
        case recording
        case scoring
        case result
    }

    @State private var phase: Phase = .idle
    @State private var scorePercent: Int?
    @State private var hypothesis: String = ""
    @State private var bannerError: String?
    @State private var recordingSeconds: Int = 0
    @State private var tick: Task<Void, Never>?

    private let recorder = ShadowReadingRecorder()
    private let whisper = WhisperSpeechRecognitionService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(String(localized: LocalizedStringResource("shadow_reading_reference_label", locale: locale)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(segment.originalText)
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if phase == .recording {
                        HStack {
                            Image(systemName: "record.circle")
                                .foregroundStyle(.red)
                            Text(String(format: String(localized: LocalizedStringResource("shadow_reading_recording_seconds", locale: locale)), recordingSeconds))
                                .font(.subheadline.monospacedDigit())
                        }
                    }

                    if let err = bannerError {
                        Text(err)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    if phase == .scoring {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(String(localized: LocalizedStringResource("shadow_reading_scoring", locale: locale)))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if phase == .result, let s = scorePercent {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(String(localized: LocalizedStringResource(String.LocalizationValue(stringLiteral: tierKey(for: s)), locale: locale)))
                                .font(.title3.weight(.semibold))
                            Text(String(format: String(localized: LocalizedStringResource("shadow_reading_score_percent", locale: locale)), s))
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.green)
                            Text(String(localized: LocalizedStringResource("shadow_reading_recognized_label", locale: locale)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(hypothesis.isEmpty ? String(localized: LocalizedStringResource("shadow_reading_no_speech", locale: locale)) : hypothesis)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.top, 4)
                    }

                    Text(String(localized: LocalizedStringResource("shadow_reading_disclaimer", locale: locale)))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                }
                .padding(20)
            }
            .navigationTitle(String(localized: LocalizedStringResource("shadow_reading_title", locale: locale)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: LocalizedStringResource("shadow_reading_done", locale: locale))) {
                        cancelTick()
                        _ = recorder.stopRecording()
                        onDismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    if phase == .idle || phase == .result {
                        Button {
                            Task { await startRecording() }
                        } label: {
                            Label(
                                String(localized: LocalizedStringResource("shadow_reading_start_record", locale: locale)),
                                systemImage: "mic.circle.fill"
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    } else if phase == .recording {
                        Button {
                            Task { await stopAndScore() }
                        } label: {
                            Label(
                                String(localized: LocalizedStringResource("shadow_reading_stop_and_score", locale: locale)),
                                systemImage: "stop.circle.fill"
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.bar)
            }
            .onAppear {
                onPausePlayback()
            }
            .onDisappear {
                cancelTick()
                _ = recorder.stopRecording()
            }
        }
    }

    private func tierKey(for score: Int) -> String {
        switch score {
        case 85...100: return "shadow_reading_tier_great"
        case 60..<85: return "shadow_reading_tier_ok"
        case 35..<60: return "shadow_reading_tier_weak"
        default: return "shadow_reading_tier_retry"
        }
    }

    private func cancelTick() {
        tick?.cancel()
        tick = nil
    }

    private func startRecording() async {
        bannerError = nil
        scorePercent = nil
        hypothesis = ""
        phase = .idle
        let ok = await recorder.requestPermission()
        guard ok else {
            bannerError = String(localized: LocalizedStringResource("shadow_reading_mic_denied", locale: locale))
            return
        }
        do {
            let url = recorder.makeRecordingURL()
            try recorder.startRecording(to: url)
            phase = .recording
            recordingSeconds = 0
            cancelTick()
            tick = Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    if Task.isCancelled { break }
                    recordingSeconds += 1
                    if recordingSeconds >= 60 {
                        await stopAndScore()
                        break
                    }
                }
            }
        } catch {
            bannerError = error.localizedDescription
        }
    }

    private func stopAndScore() async {
        cancelTick()
        guard let url = recorder.stopRecording() else {
            phase = .idle
            return
        }
        phase = .scoring
        bannerError = nil
        defer {
            try? FileManager.default.removeItem(at: url)
        }
        do {
            let segs = try await whisper.recognize(audioURL: url)
            let hyp = segs.map(\.text).joined()
            hypothesis = hyp
            let s = ShadowReadingTextSimilarity.scorePercent(reference: segment.originalText, hypothesis: hyp)
            scorePercent = s
            phase = .result
        } catch {
            bannerError = String(localized: LocalizedStringResource("shadow_reading_error", locale: locale)) + "\n" + error.localizedDescription
            phase = .idle
        }
    }
}
