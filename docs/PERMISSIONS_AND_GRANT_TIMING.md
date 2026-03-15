# YomiPlay 权限与授权时机说明

## 一、当前声明的权限（Info.plist）

| 键 | 用途说明 | 实际触发时机 |
|----|----------|--------------|
| **NSPhotoLibraryUsageDescription** | 从相册选择视频/音频导入 | 用户点击「从相册选择」并打开 PhotosPicker 时，由系统自动弹出 |
| **NSSpeechRecognitionUsageDescription** | 语音识别（Apple 备用方案） | 仅在使用 SFSpeechRecognizer 时触发；当前主路径为 Whisper 本地识别，**不会**主动弹出 |
| **NSMicrophoneUsageDescription** | 麦克风 | **当前代码未使用麦克风**（无录音、无实时识别），系统不会弹出此权限；建议删除以免误导用户与审核 |

## 二、授权时机是否合适

- **相册**  
  - 在用户点击「从相册选择」并进入系统相册选择界面时，由系统请求。  
  - **结论**：时机合适，无需改动。

- **语音识别**  
  - 在 `ProcessingViewModel.processWithRecognition` 中调用 `speechService.requestAuthorization()`。  
  - 主路径使用 Whisper（`WhisperSpeechRecognitionService`），其 `requestAuthorization()` 直接返回 `true`，不弹系统框。  
  - 只有在走 Apple 语音识别备用路径时才会弹出系统「语音识别」权限。  
  - **结论**：请求发生在「用户已选好文件并进入处理流程」之后，属于**按需、场景内**请求，时机合适。

- **麦克风**  
  - 工程内无 `AVCaptureDevice.requestAccess` 或任何录音/实时识别逻辑。  
  - **结论**：未使用麦克风，建议从 Info.plist 中移除 `NSMicrophoneUsageDescription`。

## 三、建议操作

1. **移除未使用的麦克风说明**  
   - 删除 Info.plist 中的 `NSMicrophoneUsageDescription`，避免审核与用户误解。

2. **（可选）首次语音权限前的说明**  
   - 若将来在 Apple 语音识别路径下首次调用 `requestAuthorization()` 前，可先展示一句应用内文案（如：「为了把这段音频转成字幕，需要开启语音识别权限」），再触发系统弹窗，通过率通常更高。

3. **（可选）多语言说明**  
   - 当前 Info.plist 内说明为日文；若目标用户以中文/英文为主，可增加对应语言的 InfoPlist.strings，或把主说明改为目标语言。

## 四、总结

- **初次安装后**：不会在启动时一次性索要所有权限。  
- **相册**：仅在用户点击「从相册选择」时由系统请求，时机正确。  
- **语音识别**：仅在进入「处理流程」且使用 Apple 语音识别时请求，时机正确；主路径 Whisper 不触发该权限。  
- **麦克风**：未使用，建议删除对应 Info.plist 条目。
