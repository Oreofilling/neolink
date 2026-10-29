/// CT-Prov/1 v2.0 协议核心（骨架）：操作与错误码已冻结，编解码/分片在 M1 填充。
/// 协议文档：lowpower_camera/docs/CT_PROV_PROTOCOL.md（无事务模型，C-11）。

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

/// 设备返回的 apply 提示（仅展示，不据此轮询）。
enum ApplyHint { immediate, reconnect, reboot }
