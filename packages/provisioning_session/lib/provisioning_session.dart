/// 配置会话领域层（骨架）：统一状态机（技术设计 §11）。M2 填充迁移与资源释放。
library;

export 'src/ct_session_client.dart';

enum SessionPhase {
  selfChecking,
  scanning,
  resultsAvailable,
  scanEmpty,
  guideScanning,
  showingGuide,
  connecting,
  readingCapabilities,
  choosingSections,
  editingConfig,
  delivering,
  stored,
  operationError,
  connectionError,
  capabilityError,
  completed,
  cleaning,
}
