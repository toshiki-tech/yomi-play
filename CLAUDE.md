# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

YomiPlay is a native iOS SwiftUI application for Japanese language learning through audio/video content. It provides on-device Whisper-based speech recognition, furigana (reading aids) generation, shadow reading practice with similarity scoring, and translation features.

## Build & Development Commands

### Build the Project
```bash
cd YomiPlay
xcodebuild -project YomiPlay.xcodeproj -scheme YomiPlay -configuration Debug build
```

### Run Tests
```bash
cd YomiPlay
xcodebuild test -project YomiPlay.xcodeproj -scheme YomiPlay -destination 'platform=iOS Simulator,name=iPhone 15'
```

### Clean Build
```bash
cd YomiPlay
xcodebuild clean -project YomiPlay.xcodeproj -scheme YomiPlay
```

### Build for Device
```bash
cd YomiPlay
xcodebuild -project YomiPlay.xcodeproj -scheme YomiPlay -configuration Release -sdk iphoneos
```

## Architecture Overview

### Core Service Layer
The application follows MVVM architecture with centralized services:

- **AudioPlayerService**: AVPlayer-based audio/video playback with synchronized subtitle display, loop modes (whole track/single subtitle), inter-subtitle pause for shadow reading practice
- **WhisperSpeechRecognitionService**: On-device Whisper speech recognition using WhisperKit (Argmax). Bundled models include tiny/base/small/medium/large variants. Supports multi-language recognition (ja/en/zh/auto)
- **ShadowReadingRecorder**: Short audio recording for shadow reading practice transcription
- **DocumentStore**: JSON-based persistence for TranscriptDocument objects in Documents/SavedDocuments/
- **FuriganaService**: Generates furigana (phonetic reading aids) using CFStringTokenizer for Japanese text
- **TranslationService**: System Translation API integration for subtitle translation
- **SubscriptionManager**: StoreKit 2-based in-app purchase and subscription management

### Data Flow
1. **Import**: Audio/video/podcast URL/ZIP → ProcessingViewModel
2. **Recognition**: WhisperSpeechRecognitionService → RecognitionSegments with word-level timing
3. **Enhancement**: FuriganaService generates tokens with kanji/katakana/romaji
4. **Storage**: TranscriptDocument serialized to JSON via DocumentStore
5. **Playback**: PlayerViewModel coordinates AudioPlayerService + subtitle sync
6. **Shadow Reading**: ShadowReadingRecorder → Whisper transcription → ShadowReadingTextSimilarity scoring

### Models (Models.swift)
- **AudioSource**: Represents local/remote media with relative paths for persistence
- **TranscriptSegment**: Time-aligned subtitle with original text, tokens, translation, and language code
- **FuriganaToken**: Individual word/character with surface form, reading, romaji, English meaning (for katakana loanwords), word-level timing, and part-of-speech
- **TranscriptDocument**: Complete document with AudioSource, segments, playback position, folder association

### ViewModels
- **HomeViewModel**: Library management, import orchestration
- **ProcessingViewModel**: Audio import, recognition pipeline, furigana generation
- **PlayerViewModel**: Playback control, subtitle editing (split/merge/delete), translation, repeat modes, display settings persistence

### Key Dependencies
- **WhisperKit** (Argmax): Local Whisper model inference with bundled models
- **swift-transformers** (Hugging Face): Transformer model utilities
- **ZIPFoundation**: ZIP archive extraction for batch imports

## Important Implementation Details

### Whisper Model Management
- Models are bundled in `YomiPlay/WhisperModels/openai_whisper-{variant}/`
- Model selection persisted in UserDefaults key `whisperModelVariant`
- Recommended model auto-selected based on device memory on first launch
- Call `WhisperSpeechRecognitionService.invalidateModel()` after changing model settings

### Audio Session Handling
- Category: `.playback` with mode `.spokenAudio`
- Interruption handling (calls, notifications) preserves playback state
- Shadow reading temporarily switches to `.playAndRecord` mode

### Subtitle Timing & Synchronization
- AudioPlayerService uses 0.1s periodic time observer for subtitle sync
- Inter-subtitle pause feature: automatically pauses between consecutive subtitles for shadow reading practice
- Single subtitle loop mode: seeks back to segment.startTime when reaching endTime
- Word-level timing (Whisper word_timestamps) stored in FuriganaToken for karaoke-style highlighting

### Persistence Strategy
- TranscriptDocuments: JSON files in `Documents/SavedDocuments/{uuid}.json`
- Media files: Stored as relative paths from Documents directory for portability
- Folders (grouping): `Documents/SavedDocuments/folders.json`
- Reference counting: Media files only deleted when no documents reference them

### Language Detection & Processing
- `WhisperSpeechRecognitionService.isLikelyJapanese()`: Detects Japanese by Unicode ranges (Hiragana/Katakana/CJK)
- Non-Japanese content: `skipFurigana=true` to avoid incorrect phonetic generation
- `originalTextLanguageCode` per segment: Tracks source language for accurate shadow reading transcription
- Recognition language setting: `whisperSourceLanguage` UserDefaults key (ja/en/zh/auto)

### Display Settings Persistence
- User display preferences (showFurigana, showRomaji, showEnglish, fontSize, playbackRate) persisted in UserDefaults
- Non-Japanese recognition sources default to furigana/romaji disabled
- Translation target language follows system locale by default via `TranslationTargetLanguageOptions.defaultTargetCode()`

### Shadow Reading Flow
1. User records audio via ShadowReadingRecorder (m4a format)
2. WhisperSpeechRecognitionService transcribes with segment's `originalTextLanguageCode` as `preferredLanguageCode`
3. ShadowReadingTextSimilarity computes normalized Levenshtein similarity
4. Results displayed with color-coded similarity score

## Localization
- String localization in `Localizable.xcstrings` (Xcode String Catalog format)
- App interface language setting: `appInterfaceLanguage` UserDefaults key (system/en/ja/zh-Hans)
- `AppLocale.current` provides effective locale for non-View code
- Process state display text uses locale-aware `ProcessingState.displayText(locale:)`

## Testing Notes
- Main target: YomiPlay
- Test targets: YomiPlayTests, YomiPlayUITests
- Whisper model inference is device-dependent; use simulators for basic testing, real devices for recognition accuracy

## Common Modification Patterns

### Adding New Subtitle Edit Operations
1. Add method to PlayerViewModel (e.g., `splitCurrentSegmentAtCurrentTime()`)
2. Update `document.segments` array
3. Call `playerService.setSegments(document.segments)`
4. Call `syncRepeatModeWithPlayer()` to update loop target if needed
5. Call `saveDocument()` to persist changes

### Changing Recognition Settings
1. Update UserDefaults key (`whisperModelVariant` or `whisperSourceLanguage`)
2. Call `WhisperSpeechRecognitionService.invalidateModel()` to clear cached model
3. Next recognition will load new model/language configuration

### Extending Supported Media Types
1. Update import logic in ProcessingViewModel or HomeViewModel
2. Ensure URLs are converted to relative paths via AudioSource.relativeFilePath
3. Update DocumentStore.removeMediaFilesIfOwned() for cleanup logic
