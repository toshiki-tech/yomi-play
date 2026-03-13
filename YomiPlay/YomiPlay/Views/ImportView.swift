//
//  ImportView.swift
//  YomiPlay
//
//  新規インポート画面
//

import SwiftUI
import PhotosUI

struct ImportView: View {
    @Bindable var viewModel: HomeViewModel
    @State private var selectedVideoItem: PhotosPickerItem?
    @FocusState private var isUrlFieldFocused: Bool
    @AppStorage("enableURLImport") private var enableURLImport: Bool = true
    
    var body: some View {
        ZStack {
            mainBody
                .onChange(of: selectedVideoItem) { _, newValue in
                    if let item = newValue {
                        viewModel.handlePhotoPickerItem(item)
                        selectedVideoItem = nil
                    }
                }
                .onAppear {
                    isUrlFieldFocused = false
                }
            
            if viewModel.showSRTOption {
                optionsOverlay
                    .zIndex(1)
            }
        }
        .animation(.spring(duration: 0.3), value: viewModel.showSRTOption)
    }
    
    // MARK: - Subviews
    
    private var mainBody: some View {
        ScrollView {
            VStack(spacing: 32) {
                headerSection
                
                VStack(spacing: 16) {
                    fileImportSection
                    photoLibrarySection
                }
                
                if enableURLImport {
                    urlImportSection
                }
                
                Spacer()
            }
            .padding(20)
            .contentShape(Rectangle())
            .onTapGesture {
                isUrlFieldFocused = false
            }
        }
        .background(Color(.systemBackground).onTapGesture {
            isUrlFieldFocused = false
        })
        .disabled(viewModel.showSRTOption) // 選択中は背面を操作不可にする
    }
    
    private var optionsOverlay: some View {
        ZStack {
            // 背景のボカシ
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    viewModel.pendingAudioSource = nil
                    viewModel.showSRTOption = false
                }
            
            // 選択カード
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("home_subtitle_choice_title")
                        .font(.headline)
                    Text("home_subtitle_choice_message")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 8)
                
                VStack(spacing: 12) {
                    // AI音声認識
                    choiceCard(
                        title: "home_subtitle_choice_skip_button",
                        description: "use_ai_recognition",
                        image: "sparkles",
                        color: .green
                    ) {
                        viewModel.skipSRT()
                    }
                    
                    // SRTファイル
                    choiceCard(
                        title: "home_subtitle_choice_srt_button",
                        description: "import_standard_subtitles",
                        image: "doc.text.fill",
                        color: .blue
                    ) {
                        viewModel.fileImportMode = .srt
                        viewModel.isFileImporterPresented = true
                    }
                    
                    // YOMIファイル
                    choiceCard(
                        title: "home_subtitle_choice_yomi_button",
                        description: "import_formatted_yomi",
                        image: "character.bubble.fill",
                        color: .orange
                    ) {
                        viewModel.fileImportMode = .yomi
                        viewModel.isFileImporterPresented = true
                    }
                }
                
                Button("cancel") {
                    viewModel.pendingAudioSource = nil
                    viewModel.showSRTOption = false
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
            )
            .padding(.horizontal, 32)
            .transition(.scale.combined(with: .opacity))
        }
    }
    
    private func choiceCard(title: LocalizedStringKey, description: LocalizedStringKey, image: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.1))
                        .frame(width: 40, height: 40)
                    Image(systemName: image)
                        .foregroundStyle(color)
                        .font(.system(size: 18, weight: .semibold))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground).opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var fileImportSection: some View {
        Button {
            viewModel.fileImportMode = .audioVideo
            viewModel.isFileImporterPresented = true
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.blue.opacity(0.1))
                    Image(systemName: "folder.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                }
                .frame(width: 50, height: 50)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("select_from_files").font(.headline)
                    Text("mp3, m4a, wav, mp4, mov").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
        }
        .buttonStyle(.plain)
    }
    
    private var photoLibrarySection: some View {
        PhotosPicker(selection: $selectedVideoItem, matching: .videos) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.purple.opacity(0.1))
                    Image(systemName: "video.fill")
                        .font(.title2)
                        .foregroundStyle(.purple)
                }
                .frame(width: 50, height: 50)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("select_from_photo_library").font(.headline)
                    Text("video_files_from_camera_roll").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
        }
        .buttonStyle(.plain)
    }
    
    private var urlImportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("load_from_url", systemImage: "link").font(.headline)
            
            HStack(spacing: 12) {
                TextField("enter_audio_video_url", text: $viewModel.urlText)
                    .textFieldStyle(.plain)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.green, lineWidth: 2))
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .focused($isUrlFieldFocused)
                
                Button {
                    isUrlFieldFocused = false
                    viewModel.loadFromURL()
                } label: {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(viewModel.urlText.isEmpty ? Color.secondary : Color.green)
                }
                .disabled(viewModel.urlText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemBackground)))
    }
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.linearGradient(colors: [.green, .green.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .symbolRenderingMode(.hierarchical)
            
            VStack(spacing: 4) {
                Text("YomiPlay").font(.largeTitle).fontWeight(.bold)
                Text("Japanese Learning & Subtitles").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 20)
    }
}
