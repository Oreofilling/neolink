/// config.set / communication.scan / config.get 的结果形状（§9、§10）。
library;

import 'package:ct_prov_core/ct_prov_core.dart';

import 'session_exception.dart';

/// config.set 结果：已持久化节名 + apply 提示（仅展示，不据此轮询）。
final class SetConfigResult {
  const SetConfigResult({required this.stored, this.apply});

  factory SetConfigResult.fromResponse(ProvResponse response) {
    if (!response.ok) {
      throw _rejected(response);
    }
    if (response.opName != '${ProvOp.configSet.wireName}.result') {
      throw ProvSessionException('config_set_op', response.opName);
    }
    final data = response.data;
    final stored = data?['stored'];
    if (stored is! List || stored.any((entry) => entry is! String)) {
      throw const ProvSessionException(
        'config_set_shape',
        'stored must be an array of strings',
      );
    }
    final apply = data?['apply'];
    if (apply is! String?) {
      throw const ProvSessionException(
        'config_set_shape',
        'apply must be a string',
      );
    }
    return SetConfigResult(stored: List<String>.from(stored), apply: apply);
  }

  final List<String> stored;
  final String? apply;
}

/// 扫描到的一个网络条目。
final class ScanNetwork {
  const ScanNetwork({
    required this.networkId,
    required this.displayName,
    required this.signal,
    this.channel,
    this.extras = const {},
  });

  factory ScanNetwork.fromWire(Map<Object?, Object?> entry) {
    final networkId = entry['network_id'];
    final displayName = entry['display_name'];
    final signal = entry['signal'];
    if (networkId is! String || displayName is! String || signal is! int) {
      throw const ProvSessionException(
        'scan_shape',
        'item requires network_id/display_name strings and int signal',
      );
    }
    final channel = entry['channel'];
    if (channel is! int?) {
      throw const ProvSessionException(
        'scan_shape',
        'channel must be an int when present',
      );
    }
    return ScanNetwork(
      networkId: networkId,
      displayName: displayName,
      signal: signal,
      channel: channel,
      // 已声明的扩展字段（halow 的 country/bandwidth_khz 等）原样保留。
      extras: Map<String, Object?>.fromEntries(
        entry.entries
            .map(
              (e) => MapEntry(
                  e.key is String ? e.key as String : '${e.key}', e.value),
            )
            .where(
              (e) =>
                  e.key != 'network_id' &&
                  e.key != 'display_name' &&
                  e.key != 'signal' &&
                  e.key != 'channel',
            ),
      ),
    );
  }

  /// network_id（SSID 等）。
  final String networkId;
  final String displayName;

  /// dBm。
  final int signal;
  final int? channel;

  /// 其余已声明字段（如 halow 条目的 country）。
  final Map<String, Object?> extras;
}

/// communication.scan 结果：一页条目 + 游标。
final class ScanNetworksResult {
  const ScanNetworksResult({
    required this.section,
    required this.items,
    required this.more,
    required this.cursor,
  });

  factory ScanNetworksResult.fromResponse(ProvResponse response) {
    if (!response.ok) {
      throw _rejected(response);
    }
    if (response.opName != '${ProvOp.communicationScan.wireName}.result') {
      throw ProvSessionException('scan_op', response.opName);
    }
    final data = response.data;
    final section = data?['section'];
    final items = data?['items'];
    final more = data?['more'];
    final cursor = data?['cursor'];
    if (section is! String) {
      throw const ProvSessionException(
        'scan_shape',
        'section must be a string',
      );
    }
    if (items is! List || items.any((entry) => entry is! Map)) {
      throw const ProvSessionException(
        'scan_shape',
        'items must be an array of objects',
      );
    }
    if (more is! bool || cursor is! String) {
      throw const ProvSessionException(
        'scan_shape',
        'more must be bool and cursor must be string',
      );
    }
    return ScanNetworksResult(
      section: section,
      items: [
        for (final entry in items)
          ScanNetwork.fromWire(entry.cast<Object?, Object?>()),
      ],
      more: more,
      cursor: cursor,
    );
  }

  final String section;
  final List<ScanNetwork> items;

  /// true 时 [cursor] 指向下一页（对客户端不透明，仅当前连接内有效）。
  final bool more;
  final String cursor;
}

/// ok:false 统一映射：reason 用错误码小写蛇形（UI 可直接按码分支），
/// message 保留原文（含大写错误码便于诊断）。
ProvSessionException _rejected(ProvResponse response) {
  final error = response.error;
  final code = error?.codeName ?? 'UNKNOWN';
  return ProvSessionException(
    code.toLowerCase(),
    '$code: ${error?.message ?? ''}',
  );
}
