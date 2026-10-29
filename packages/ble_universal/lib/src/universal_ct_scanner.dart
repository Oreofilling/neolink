/// CT-Prov 扫描桥：universal_ble 的 BleDevice 流 → §4 解析结果。
library;

import 'dart:async';

import 'package:ble_adapter/ble_adapter.dart';
import 'package:universal_ble/universal_ble.dart';

import 'ct_adv_source.dart';

/// 扫描结果记录：协议视图 + 连接所需的平台设备句柄与 RSSI。
final class CtScanRecord {
  const CtScanRecord({
    required this.deviceId,
    required this.rssi,
    required this.info,
  });

  final String deviceId;
  final int? rssi;
  final CtDiscoveredDevice info;
}

/// 按 Service UUID 过滤扫描，把 Service Data 归一成 27 字节广播后交给
/// ble_adapter 解析；scan response 名字经 [buildScanResponse] 重建合入。
/// 每个广播帧产出一条记录，UI 层按 deviceId 去重或取 [latest]。
final class UniversalCtScanner {
  final StreamController<CtScanRecord> _controller =
      StreamController<CtScanRecord>.broadcast();
  final Map<String, CtScanRecord> _latestById = <String, CtScanRecord>{};
  StreamSubscription<BleDevice>? _scanSub;
  bool _scanning = false;

  /// 扫描结果流（广播；每帧一条）。
  Stream<CtScanRecord> get records => _controller.stream;

  /// 每个设备最近一条记录的只读快照。
  Map<String, CtScanRecord> get latest => Map.unmodifiable(_latestById);

  bool get isScanning => _scanning;

  Future<void> start() async {
    if (_scanning) return;
    _scanning = true;
    _scanSub = UniversalBle.scanStream.listen(_onDevice);
    try {
      await UniversalBle.startScan(
        scanFilter: const ScanFilter(
          withServices: [kCtProvServiceUuid],
        ),
      );
    } catch (_) {
      // 启动失败不留半开状态：停订阅并原样抛给调用方。
      await _scanSub?.cancel();
      _scanSub = null;
      _scanning = false;
      rethrow;
    }
  }

  Future<void> stop() async {
    if (!_scanning) return;
    _scanning = false;
    await _scanSub?.cancel();
    _scanSub = null;
    await UniversalBle.stopScan();
  }

  /// 释放流资源（不停扫描；扫描中请先 stop）。
  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }

  void _onDevice(BleDevice device) {
    final value = _serviceDataValue(device);
    if (value == null) return;
    final advData = buildAdvertisingData(value);
    if (advData == null) return;
    var info = parseAdvertisingData(advData);
    if (info == null) return;
    info = applyScanResponse(info, buildScanResponse(device.name));
    final record = CtScanRecord(
      deviceId: device.deviceId,
      rssi: device.rssi,
      info: info,
    );
    _latestById[device.deviceId] = record;
    _controller.add(record);
  }

  /// universal_ble 用 BleUuidParser 把键归一为小写 UUID；仍按三种大小写
  /// 形态兜底查找，避免平台实现差异漏掉目标服务。
  Uint8List? _serviceDataValue(BleDevice device) {
    final serviceData = device.serviceData;
    if (serviceData.isEmpty) return null;
    return serviceData[kCtProvServiceUuid.toLowerCase()] ??
        serviceData[kCtProvServiceUuid] ??
        serviceData[kCtProvServiceUuid.toUpperCase()];
  }
}
