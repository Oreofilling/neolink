/// 协议操作与错误码（v2.0 全集，随信封层使用的枚举与反查助手）。
library;

/// 协议操作（v2.0 全集：6 个）。
enum ProvOp {
  deviceInfoGet('device.info.get'),
  communicationCapabilitiesGet('communication.capabilities.get'),
  communicationScan('communication.scan'),
  configSet('config.set'),
  configGet('config.get'),
  sessionClose('session.close');

  const ProvOp(this.wireName);
  final String wireName;
}

/// 按 op 名反查枚举；未知 op 返回 null（信封解码对未知 op 保持可解析）。
ProvOp? provOpFromWire(String opName) {
  for (final op in ProvOp.values) {
    if (op.wireName == opName) return op;
  }
  return null;
}

/// 错误码（v2.0 全集：9 个，只覆盖校验与存储，无运行时联网错误）。
enum ProvErrorCode {
  invalidMessage('INVALID_MESSAGE'),
  unsupportedVersion('UNSUPPORTED_VERSION'),
  unsupportedOperation('UNSUPPORTED_OPERATION'),
  invalidArgument('INVALID_ARGUMENT'),
  busy('BUSY'),
  sectionNotSupported('SECTION_NOT_SUPPORTED'),
  fieldNotSupported('FIELD_NOT_SUPPORTED'),
  storageFailed('STORAGE_FAILED'),
  internalError('INTERNAL_ERROR');

  const ProvErrorCode(this.wireName);
  final String wireName;
}

/// 按错误码原文反查枚举；未知错误码返回 null。
ProvErrorCode? provErrorCodeFromWire(String codeName) {
  for (final code in ProvErrorCode.values) {
    if (code.wireName == codeName) return code;
  }
  return null;
}

/// 设备返回的 apply 提示（仅展示，不据此轮询）。
enum ApplyHint { immediate, reconnect, reboot }
