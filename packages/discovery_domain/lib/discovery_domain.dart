/// 设备发现领域层（骨架）：三路通道与候选归一化。M2 接入 BLE/AP/CT-Disc 适配器。
/// 禁止与通讯模式（CommunicationMode）混用（决策 C-03）。

library;

enum DiscoveryChannel { ble, accessPoint, ctDisc }

/// 当前扫描任务内的临时候选（不落盘、不跨任务）。
final class DiscoveryCandidate {
  const DiscoveryCandidate({
    required this.candidateId,
    required this.macSuffix,
    required this.channels,
    required this.provisionable,
    required this.busy,
    required this.lastSeen,
    this.modelHint,
  });

  final String candidateId;
  final String? modelHint;
  final String macSuffix;
  final Set<DiscoveryChannel> channels;
  final bool provisionable;
  final bool busy;
  final DateTime lastSeen;
}
