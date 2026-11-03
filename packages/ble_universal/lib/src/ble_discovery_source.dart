/// BLE 通道发现源：UniversalCtScanner 记录 → 发现领域候选。
///
/// 实现 discovery_domain 的 [DiscoverySource] 端口（AP / CT-Disc 接入时
/// 实现同一端口并入注册表）。
library;

import 'dart:async';

import 'package:discovery_domain/discovery_domain.dart';

import 'universal_ct_scanner.dart';

/// 把一条 BLE 扫描记录归一成发现候选。
///
/// 标志位缺失（负载不可靠，format_version 不支持等）时按可继续取向：
/// busy 取 false、provisionable 取 true——协议要求不得因负载不认识而
/// 隐藏或拒绝设备（§4.2.2）；已知忙时强制不可配置。[now] 仅测试注入用。
DiscoveryCandidate bleCandidateFromRecord(
  CtScanRecord record, {
  DateTime Function()? now,
}) {
  final busy = record.info.busy ?? false;
  return DiscoveryCandidate(
    candidateId: record.deviceId,
    macSuffix: record.info.macSuffix?.toUpperCase(),
    modelHint: record.info.modelCodeName,
    channels: const {DiscoveryChannel.ble},
    provisionable: busy ? false : (record.info.provisionable ?? true),
    busy: busy,
    lastSeen: (now ?? DateTime.now)(),
    signal: record.rssi,
  );
}

/// BLE 发现源：包一层 [UniversalCtScanner]，把记录流映射为候选流。
final class BleDiscoverySource implements DiscoverySource {
  BleDiscoverySource({UniversalCtScanner? scanner, DateTime Function()? now})
    : _scanner = scanner ?? UniversalCtScanner(),
      _now = now;

  final UniversalCtScanner _scanner;
  final DateTime Function()? _now;

  @override
  Stream<DiscoveryCandidate> get candidates => _scanner.records.map(
    (record) => bleCandidateFromRecord(record, now: _now),
  );

  @override
  Future<void> start() => _scanner.start();

  @override
  Future<void> stop() => _scanner.stop();
}
