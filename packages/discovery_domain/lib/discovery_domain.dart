/// 设备发现领域层：三路通道（BLE / AP / CT-Disc）的候选模型与归一化。
///
/// 领域层不依赖任何传输实现；各通道适配器实现 [DiscoverySource]，把
/// 通道记录归一成 [DiscoveryCandidate] 后交给 [DiscoveryRegistry] 合并。
/// 禁止与通讯模式（CommunicationMode）混用（决策 C-03）。
library;

import 'dart:async';

export 'src/composite_discovery_source.dart';

enum DiscoveryChannel { ble, accessPoint, ctDisc }

/// 通道可用性结论：limited 表示能力受限（可继续但降级标注，如无线网卡
/// 被禁用、通道本版未接入），unavailable 表示该通道完全不可用。
enum ChannelCapability { available, limited, unavailable }

/// 单通道自检结论。[reason] 为稳定标识（UI 映射文案），[detail] 携带
/// 原始诊断串（日志/诊断区直接展示，不参与本地化）。
final class ChannelReadiness {
  const ChannelReadiness({
    required this.channel,
    required this.capability,
    required this.reason,
    this.detail,
  });

  final DiscoveryChannel channel;
  final ChannelCapability capability;

  /// 稳定标识，如 'powered_off' / 'no_wlan_adapter'；available 时为
  /// 'ready' 类取值。
  final String reason;

  final String? detail;
}

/// 环境自检汇总：三路通道各自结论 + 是否可进入扫描。
final class EnvironmentCheckReport {
  const EnvironmentCheckReport({required this.channels});

  final List<ChannelReadiness> channels;

  /// 至少一条通道完全可用即可继续（仅其余通道受限不阻塞，技术设计
  /// §11「环境就绪或仅通道受限」）；全部受限/不可用时停留自检。
  bool get canProceed =>
      channels.any((entry) => entry.capability == ChannelCapability.available);

  /// 按通道取结论；报告未覆盖该通道时返回 null。
  ChannelReadiness? channel(DiscoveryChannel channel) {
    for (final entry in channels) {
      if (entry.channel == channel) return entry;
    }
    return null;
  }
}

/// 当前扫描任务内的临时候选（不落盘、不跨任务）。
///
/// [macSuffix] 是跨通道合并键（设备规范主 MAC 后 6 位十六进制大写）；
/// 广播负载不可靠（format_version 不支持等）时可为 null，此时退化为按
/// [candidateId] 独立成条。跨通道连接所需的各通道句柄映射由会话层在
/// 候选之外维护。
final class DiscoveryCandidate {
  const DiscoveryCandidate({
    required this.candidateId,
    required this.channels,
    required this.provisionable,
    required this.busy,
    required this.lastSeen,
    this.macSuffix,
    this.modelHint,
    this.signal,
  });

  /// 通道内稳定的候选标识（BLE 为平台设备 ID）。合并时保持首见值。
  final String candidateId;

  /// 设备规范主 MAC 后 6 位十六进制大写；负载不可靠时为 null。
  final String? macSuffix;

  /// 已知型号名（未知型号为 null，仍应展示并允许连接）。
  final String? modelHint;

  /// 该候选出现过的通道集合。
  final Set<DiscoveryChannel> channels;

  /// 是否当前允许发起配置；任一记录忙时必须为 false（§4.2.2）。
  final bool provisionable;

  /// 最近一条记录是否报告忙。
  final bool busy;

  /// 最近一次收到记录的时间。
  final DateTime lastSeen;

  /// 最近一次记录的信号强度提示（BLE RSSI，dBm）；缺失为 null。
  final int? signal;

  /// 合并/刷新用的不可变拷贝（[candidateId] 不变，保持首见标识）。
  DiscoveryCandidate copyWith({
    String? macSuffix,
    String? modelHint,
    Set<DiscoveryChannel>? channels,
    bool? provisionable,
    bool? busy,
    DateTime? lastSeen,
    int? signal,
  }) =>
      DiscoveryCandidate(
        candidateId: candidateId,
        macSuffix: macSuffix ?? this.macSuffix,
        modelHint: modelHint ?? this.modelHint,
        channels: channels ?? this.channels,
        provisionable: provisionable ?? this.provisionable,
        busy: busy ?? this.busy,
        lastSeen: lastSeen ?? this.lastSeen,
        signal: signal ?? this.signal,
      );
}

/// 发现源端口：各通道适配器实现（BLE 已接入；AP / CT-Disc 预留，
/// 接入时实现同一端口即可并入 [DiscoveryRegistry]）。
abstract interface class DiscoverySource {
  /// 归一后的候选流（每帧一条，未跨通道合并）。
  Stream<DiscoveryCandidate> get candidates;

  /// 启动通道扫描；已启动时为空操作。
  Future<void> start();

  /// 停止通道扫描并回收订阅；未启动时为空操作。
  Future<void> stop();
}

/// 跨通道候选归一化：按 macSuffix（缺失退化为 candidateId）合并；
/// 超时淘汰由调用方按扫描节奏驱动 [sweepExpired]。
final class DiscoveryRegistry {
  final Map<String, DiscoveryCandidate> _byKey = <String, DiscoveryCandidate>{};
  final StreamController<DiscoveryCandidate> _updates =
      StreamController<DiscoveryCandidate>.broadcast();

  /// 合并结果流：每次 [absorb] 发出该候选的最新合并值。
  Stream<DiscoveryCandidate> get updates => _updates.stream;

  /// 当前候选快照（首见顺序）。
  List<DiscoveryCandidate> get snapshot =>
      List<DiscoveryCandidate>.unmodifiable(_byKey.values);

  /// 并入一条通道记录；同键时产出新的合并候选（不可变，不原地改）。
  void absorb(DiscoveryCandidate candidate) {
    final key = _keyOf(candidate);
    final existing = _byKey[key];
    final merged = existing == null ? candidate : _merge(existing, candidate);
    _byKey[key] = merged;
    _updates.add(merged);
  }

  /// 淘汰 [now] 前 [ttl] 未再出现的候选，返回被移除项。
  List<DiscoveryCandidate> sweepExpired(
    DateTime now, {
    Duration ttl = const Duration(seconds: 12),
  }) {
    final expired = <DiscoveryCandidate>[];
    _byKey.removeWhere((_, candidate) {
      if (now.difference(candidate.lastSeen) > ttl) {
        expired.add(candidate);
        return true;
      }
      return false;
    });
    return expired;
  }

  String _keyOf(DiscoveryCandidate candidate) =>
      (candidate.macSuffix ?? candidate.candidateId).toUpperCase();

  /// 合并规则：candidateId/macSuffix/modelHint 取首见非空值；channels
  /// 并集；lastSeen 取较晚；signal 取最近非空；busy 与 provisionable
  /// 跟随最近一条记录（忙时强制不可配置，§4.2.2）。跨通道标志仲裁
  /// 待 AP / CT-Disc 接入时再定义。
  DiscoveryCandidate _merge(
    DiscoveryCandidate older,
    DiscoveryCandidate newer,
  ) =>
      older.copyWith(
        macSuffix: older.macSuffix ?? newer.macSuffix,
        modelHint: older.modelHint ?? newer.modelHint,
        channels: <DiscoveryChannel>{...older.channels, ...newer.channels},
        busy: newer.busy,
        provisionable: newer.busy ? false : newer.provisionable,
        lastSeen: newer.lastSeen.isAfter(older.lastSeen)
            ? newer.lastSeen
            : older.lastSeen,
        signal: newer.signal ?? older.signal,
      );
}
