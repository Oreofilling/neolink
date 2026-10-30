/// universal_ble 的 CtGattChannel 实现：连接、发现、配对加密、MTU、订阅
/// 与读写（§3 连接序列：Read META → Subscribe D2C → MTU → 加密 → 请求）。
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:ble_adapter/ble_adapter.dart';
import 'package:universal_ble/universal_ble.dart';

import 'enum_retry.dart';

/// MTU 目标值：247 覆盖 device.info 单帧；Windows 在连接时自动协商，
/// requestMtu 返回实际生效值。
const int kCtProvTargetMtu = 247;

final class UniversalCtGattChannel implements CtGattChannel {
  UniversalCtGattChannel._(this._deviceId, this._mtu, this.meta);

  final String _deviceId;
  final int _mtu;
  final StreamController<int> _mtuChanges = StreamController<int>.broadcast();
  bool _closed = false;

  /// open 阶段读到的 META（§4.3，明文可读，作为设备身份旁证）。
  final CtMetaInfo? meta;

  /// 走完 §3 连接序列并返回就绪通道。任一步失败先回滚断开再抛错，
  /// 不留半开连接。
  ///
  /// Windows 端插件在连接瞬间缓存 GATT 表，偶发缓存到空表
  /// （真机复现「characteristics missing」）；重发现无效，必须
  /// 断开重连整轮重试（见 [runWithEnumRetry]）。单轮失败自回滚，
  /// 设备在断开后立刻重新广播，重连成本约 1-2 秒。
  static Future<UniversalCtGattChannel> open(
    String deviceId, {
    int targetMtu = kCtProvTargetMtu,
    Duration timeout = const Duration(seconds: 15),
  }) {
    return runWithEnumRetry(
      () => _openOnce(deviceId, targetMtu: targetMtu, timeout: timeout),
    );
  }

  static Future<UniversalCtGattChannel> _openOnce(
    String deviceId, {
    int targetMtu = kCtProvTargetMtu,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    try {
      await UniversalBle.connect(deviceId, timeout: timeout);

      final services = await UniversalBle.discoverServices(
        deviceId,
        timeout: timeout,
      );
      _validateCharacteristics(services);

      // §4.3：META 明文可读；读不到只降级（meta=null），不阻断连接。
      CtMetaInfo? meta;
      try {
        final raw = await UniversalBle.read(
          deviceId,
          kCtProvServiceUuid,
          kMetaCharacteristicUuid,
          timeout: timeout,
        );
        meta = parseMeta(raw.toList());
      } catch (_) {
        meta = null;
      }

      await UniversalBle.subscribeIndications(
        deviceId,
        kCtProvServiceUuid,
        kD2cCharacteristicUuid,
        timeout: timeout,
      );

      final mtu = await UniversalBle.requestMtu(deviceId, targetMtu);

      // §4.4：C2D 要求加密链路（Just Works）。仅系统级配对平台主动 pair；
      // 已配对则跳过。Linux/macOS 走连接内加密，pair 调用由上层按需触发。
      if (BleCapabilities.hasSystemPairingApi) {
        final paired = await UniversalBle.isPaired(deviceId);
        if (paired != true) {
          await UniversalBle.pair(deviceId);
        }
      }

      final channel = UniversalCtGattChannel._(deviceId, mtu, meta);
      // 协商结果立刻播报，让传输层按新 MTU 重建重组器。
      channel._mtuChanges.add(mtu);
      return channel;
    } catch (_) {
      try {
        await UniversalBle.disconnect(deviceId);
      } catch (_) {
        // 回滚失败不掩盖原始错误。
      }
      rethrow;
    }
  }

  /// 校验 CT-Prov 服务与三个特征齐全（UUID 大小写按平台归一后比较）。
  static void _validateCharacteristics(List<BleService> services) {
    final serviceLower = kCtProvServiceUuid.toLowerCase();
    final expected = <String>{
      kC2dCharacteristicUuid.toLowerCase(),
      kD2cCharacteristicUuid.toLowerCase(),
      kMetaCharacteristicUuid.toLowerCase(),
    };
    for (final service in services) {
      if (service.uuid.toLowerCase() != serviceLower) continue;
      final found = service.characteristics
          .map((characteristic) => characteristic.uuid.toLowerCase())
          .toSet();
      final missing = expected.difference(found);
      if (missing.isNotEmpty) {
        throw StateError('CT-Prov characteristics missing: $missing');
      }
      return;
    }
    throw StateError('CT-Prov service not found after discovery');
  }

  @override
  int get mtu => _mtu;

  @override
  Stream<int> get mtuChanges => _mtuChanges.stream;

  /// C2D 写入：默认 withResponse 写请求，与固件端 F_WRITE 权限一致。
  @override
  Future<void> writeC2d(List<int> frame) async {
    _ensureOpen();
    await UniversalBle.write(
      _deviceId,
      kCtProvServiceUuid,
      kC2dCharacteristicUuid,
      Uint8List.fromList(frame),
    );
  }

  /// D2C 指示流（广播；open 阶段已订阅）。
  @override
  Stream<List<int>> get d2cFrames =>
      UniversalBle.characteristicValueStream(
        _deviceId,
        kD2cCharacteristicUuid,
      ).map((bytes) => bytes.toList());

  /// 再次读取 META（一般用 open 阶段的 [meta] 即可）。
  Future<CtMetaInfo?> readMeta() async {
    _ensureOpen();
    final raw = await UniversalBle.read(
      _deviceId,
      kCtProvServiceUuid,
      kMetaCharacteristicUuid,
    );
    return parseMeta(raw.toList());
  }

  /// 退订 D2C 并断开链路（幂等）。
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await UniversalBle.unsubscribe(
        _deviceId,
        kCtProvServiceUuid,
        kD2cCharacteristicUuid,
      );
    } finally {
      await _mtuChanges.close();
      await UniversalBle.disconnect(_deviceId);
    }
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('CT-Prov channel already closed');
    }
  }
}
