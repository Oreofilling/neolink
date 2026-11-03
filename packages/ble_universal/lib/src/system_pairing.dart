/// 系统配对编排（§4.4 桌面流）：在打开 GATT 通道之前建立 OS 侧 bond。
///
/// Windows 走宿主 runner（example / desktop_app）实现的原生配对通道
/// `neolink/windows_pairing`——CustomPairAsync(ConfirmOnly, Encryption)
/// 保留完整 DevicePairingResultStatus，并避开 universal_ble pair() 失败
/// 掀掉插件连接注册表的路径；通道缺失时回退 UniversalBle.pair。无系统
/// 配对 API 的平台交给设备侧 CONNECT 即发的 SMP 安全请求兜底。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:universal_ble/universal_ble.dart';

/// Windows 宿主 runner 侧的原生配对通道。
///
/// C++ 侧实现两个方法：`pair`（参数为设备 ID 字符串，返回状态名）与
/// `log`（诊断转录，写入 %TEMP% 日志文件）。
const MethodChannel kWindowsPairingChannel = MethodChannel(
  'neolink/windows_pairing',
);

/// 原生系统配对失败。
final class CtPairingException implements Exception {
  const CtPairingException(this.message);

  /// 失败描述（含 Windows 回报的 DevicePairingResultStatus 名）。
  final String message;

  @override
  String toString() => 'CtPairingException: $message';
}

/// 系统配对编排器；构造钩子仅测试注入用，生产路径用默认实现。
final class CtSystemPairing {
  CtSystemPairing({
    Future<bool?> Function(String deviceId)? isPaired,
    Future<String> Function(String deviceId, Duration timeout)? nativePair,
    Future<void> Function(String deviceId, Duration timeout)? fallbackPair,
    bool Function()? hasSystemPairingApi,
  }) : _isPaired = isPaired ?? _defaultIsPaired,
       _nativePair = nativePair ?? _defaultNativePair,
       _fallbackPair =
           fallbackPair ??
           ((deviceId, timeout) =>
               UniversalBle.pair(deviceId, timeout: timeout)),
       _hasSystemPairingApi =
           hasSystemPairingApi ?? (() => BleCapabilities.hasSystemPairingApi);

  final Future<bool?> Function(String deviceId) _isPaired;
  final Future<String> Function(String deviceId, Duration timeout) _nativePair;
  final Future<void> Function(String deviceId, Duration timeout) _fallbackPair;
  final bool Function() _hasSystemPairingApi;

  static Future<bool?> _defaultIsPaired(String deviceId) =>
      UniversalBle.isPaired(deviceId);

  static Future<String> _defaultNativePair(String deviceId, Duration timeout) =>
      kWindowsPairingChannel
          .invokeMethod<String>('pair', deviceId)
          .timeout(timeout)
          .then((status) => status ?? 'Unknown');

  /// 确保设备已建立系统 bond；已配对则直接复用。
  ///
  /// [onStep] 接收分步进度（真机排障用：失败前的最后一条即失败点）。
  /// 配对失败抛 [CtPairingException]（原生路径）或底层异常（回退路径），
  /// 由调用方决定是否继续开通道。
  Future<void> establish(
    String deviceId, {
    Duration timeout = const Duration(seconds: 15),
    void Function(String step)? onStep,
  }) async {
    final paired = await _isPaired(deviceId);
    onStep?.call('pre-open: isPaired=$paired');
    if (paired == true) return;

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      onStep?.call('pre-open: system pairing requested');
      try {
        final status = await _nativePair(deviceId, timeout);
        onStep?.call('pre-open: Windows PairAsync status=$status');
        return;
      } on MissingPluginException {
        // 宿主 runner 未实现原生通道：回退 universal_ble 自带实现。
        onStep?.call('pre-open: native channel missing; fallback');
      } on TimeoutException {
        throw const CtPairingException(
          'native PairAsync timed out without a status',
        );
      } on PlatformException catch (error) {
        throw CtPairingException(error.message ?? error.code);
      }
      await _fallbackPair(deviceId, timeout);
      return;
    }

    if (!_hasSystemPairingApi()) {
      // 无系统配对 API 的平台：设备侧在 CONNECT 即发 SMP 安全请求，
      // 由链路层自行完成配对加密（固件侧为未配对客户端设计的兜底）。
      onStep?.call(
        'pre-open: no system pairing API; '
        'relying on device security request',
      );
      return;
    }
    onStep?.call('pre-open: system pairing requested');
    await _fallbackPair(deviceId, timeout);
  }
}

/// 便捷入口：以默认钩子执行一次系统配对编排（见 [CtSystemPairing]）。
Future<void> establishSystemBond(
  String deviceId, {
  Duration timeout = const Duration(seconds: 15),
  void Function(String step)? onStep,
}) => CtSystemPairing().establish(deviceId, timeout: timeout, onStep: onStep);
