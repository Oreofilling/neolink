/// 会话层异常类型（会话客户端与状态机共用）。
library;

/// 会话客户端异常：reason 为稳定标识（供 UI 映射文案），message 携带
/// 设备侧详情。不透传信封异常 —— 那是协议层损坏信号，走传输层的
/// frameErrors。
final class ProvSessionException implements Exception {
  const ProvSessionException(this.reason, [this.message]);

  final String reason;
  final String? message;

  @override
  String toString() => message == null
      ? 'ProvSessionException($reason)'
      : 'ProvSessionException($reason: $message)';
}
