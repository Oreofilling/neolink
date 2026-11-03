/// 桌面端环境探测（M2-3）：BLE 射频 + WLAN 网卡（AP 通道）+ CT-Disc
/// 预留，汇总为 [EnvironmentCheckReport]。
///
/// 网卡枚举用 PowerShell Get-NetAdapter（对象输出，随系统语言无关；
/// netsh 文本输出会随 locale 变化，不采用）。探测失败按该通道
/// unavailable 处理并携带原因，不阻塞其余通道。
library;

import 'dart:convert';
import 'dart:io';

import 'package:ble_universal/ble_universal.dart';

/// 无线网卡在 Get-NetAdapter 里的 PhysicalMediaType 取值。
const String kWlanMediaType = 'Native 802.11';

/// 网卡枚举命令（ConvertTo-Json 单网卡时输出对象而非数组，解析层兼容）。
const String kAdapterQuery =
    'Get-NetAdapter -Physical | Select-Object Name,Status,PhysicalMediaType'
    ' | ConvertTo-Json -Compress';

/// 一块物理网卡的探测快照。
final class NetAdapterInfo {
  const NetAdapterInfo({
    required this.name,
    required this.status,
    required this.mediaType,
  });

  final String name;

  /// Get-NetAdapter 的 Status：Up / Disconnected / Disabled 等。
  final String status;

  /// PhysicalMediaType：'Native 802.11' 为 WLAN，'802.3' 为以太网。
  final String mediaType;
}

/// 解析 kAdapterQuery 的 JSON 输出；不可解析返回 null。
List<NetAdapterInfo>? parseNetAdapters(String jsonText) {
  Object? decoded;
  try {
    decoded = jsonDecode(jsonText);
  } on FormatException {
    return null;
  }
  final entries = decoded is List ? decoded : [decoded];
  if (entries.any((entry) => entry is! Map)) return null;
  return [
    for (final entry in entries.cast<Map>())
      NetAdapterInfo(
        name: (entry['Name'] ?? '') as String,
        status: (entry['Status'] ?? '') as String,
        mediaType: (entry['PhysicalMediaType'] ?? '') as String,
      ),
  ];
}

/// WLAN 网卡列表 → AP 通道结论：有已启用的无线网卡即可用（未连接也
/// 能扫描热点）；网卡全被禁用为受限（可修复）；无无线网卡或探测失败
/// 为不可用（UI 呈现为能力限制，而不是空列表）。
ChannelReadiness apChannelReadiness(List<NetAdapterInfo>? adapters) {
  if (adapters == null) {
    return const ChannelReadiness(
      channel: DiscoveryChannel.accessPoint,
      capability: ChannelCapability.unavailable,
      reason: 'adapter_probe_failed',
    );
  }
  final wlan = adapters
      .where((adapter) => adapter.mediaType == kWlanMediaType)
      .toList();
  if (wlan.isEmpty) {
    return const ChannelReadiness(
      channel: DiscoveryChannel.accessPoint,
      capability: ChannelCapability.unavailable,
      reason: 'no_wlan_adapter',
    );
  }
  final enabled = wlan.where((adapter) => adapter.status != 'Disabled');
  if (enabled.isEmpty) {
    return const ChannelReadiness(
      channel: DiscoveryChannel.accessPoint,
      capability: ChannelCapability.limited,
      reason: 'wlan_disabled',
    );
  }
  return const ChannelReadiness(
    channel: DiscoveryChannel.accessPoint,
    capability: ChannelCapability.available,
    reason: 'ready',
  );
}

/// CT-Disc 本版未接入：按预留通道降级标注，不参与可用性判定。
const ChannelReadiness kCtDiscReserved = ChannelReadiness(
  channel: DiscoveryChannel.ctDisc,
  capability: ChannelCapability.limited,
  reason: 'reserved',
);

/// 桌面端环境探测：BLE 与网卡枚举并行执行，失败互不牵连。
class DesktopEnvironmentProbe {
  DesktopEnvironmentProbe({
    Future<CtEnvironmentReport> Function()? probeBle,
    Future<String?> Function()? enumerateAdapters,
    this.legTimeout = const Duration(seconds: 10),
  }) : _probeBle = probeBle ?? UniversalCtEnvironment.probe,
       _enumerateAdapters = enumerateAdapters ?? _queryAdaptersViaPowerShell;

  final Future<CtEnvironmentReport> Function() _probeBle;
  final Future<String?> Function() _enumerateAdapters;

  /// Per-leg cap. A hung WinRT radio query (or a stuck PowerShell child)
  /// must resolve as a degraded report instead of wedging the caller —
  /// round-3 A2 found a wedged probe turns the re-check button permanently
  /// silent (the controller guards re-entry with an in-flight flag).
  final Duration legTimeout;

  /// 一次完整探测。BLE 探测异常按 transient 降级（携带原因）。
  Future<EnvironmentCheckReport> probe() async {
    // 用 try/catch 而不是 Future.catchError：抛错的 async 闭包实际类型
    // 参数是 Never，catchError 的运行时类型检查会拒绝处理器返回值。
    final results = await Future.wait([
      _guardedBleProbe().timeout(legTimeout, onTimeout: _bleTimedOut),
      _guardedAdapters().timeout(legTimeout, onTimeout: () => null),
    ]);
    final bleReport = results[0] as CtEnvironmentReport;
    final adapterJson = results[1] as String?;
    return EnvironmentCheckReport(
      channels: [
        bleChannelReadiness(bleReport),
        apChannelReadiness(
          adapterJson == null ? null : parseNetAdapters(adapterJson),
        ),
        kCtDiscReserved,
      ],
    );
  }

  static CtEnvironmentReport _bleTimedOut() => const CtEnvironmentReport(
    readiness: CtBleReadiness.transient,
    detail: 'probe timed out',
  );

  Future<CtEnvironmentReport> _guardedBleProbe() async {
    try {
      return await _probeBle();
    } catch (error) {
      return CtEnvironmentReport(
        readiness: CtBleReadiness.transient,
        detail: 'probe failed: $error',
      );
    }
  }

  Future<String?> _guardedAdapters() async {
    try {
      return await _enumerateAdapters();
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _queryAdaptersViaPowerShell() async {
    if (!Platform.isWindows) return null;
    final result = await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      kAdapterQuery,
    ]);
    if (result.exitCode != 0) return null;
    return result.stdout as String;
  }
}
