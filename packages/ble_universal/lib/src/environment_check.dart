/// 客户端环境自检（SessionPhase.selfChecking 的具体载体）：探测本机蓝牙
/// 可用性与运行时权限，给出能否扫描的结论与修复动作。
library;

import 'package:universal_ble/universal_ble.dart';

/// 自检结论。transient（unknown/resetting）稍后重试即可恢复。
enum CtBleReadiness {
  ready,
  poweredOff,
  unauthorized,
  unsupported,
  transient,
}

/// 一次自检的结果；detail 为英文诊断串（PoC 工具直接展示）。
final class CtEnvironmentReport {
  const CtEnvironmentReport({required this.readiness, required this.detail});

  final CtBleReadiness readiness;
  final String detail;

  bool get canScan => readiness == CtBleReadiness.ready;
}

/// 平台可用性 + 权限 → 自检结论（纯映射，可单测）。
/// 权限未授予优先于射频状态：授权后 availability 才有意义。
CtBleReadiness ctReadinessFrom(
  AvailabilityState state, {
  bool? permissionGranted,
}) {
  if (permissionGranted == false) return CtBleReadiness.unauthorized;
  return switch (state) {
    AvailabilityState.poweredOn => CtBleReadiness.ready,
    AvailabilityState.poweredOff => CtBleReadiness.poweredOff,
    AvailabilityState.unauthorized => CtBleReadiness.unauthorized,
    AvailabilityState.unsupported => CtBleReadiness.unsupported,
    AvailabilityState.unknown || AvailabilityState.resetting =>
      CtBleReadiness.transient,
  };
}

String _describe(AvailabilityState state) => switch (state) {
      AvailabilityState.poweredOn => 'radio on',
      AvailabilityState.poweredOff => 'radio off',
      AvailabilityState.unauthorized => 'app not authorized',
      AvailabilityState.unsupported => 'no bluetooth support',
      AvailabilityState.resetting => 'radio resetting',
      AvailabilityState.unknown => 'state unknown',
    };

final class UniversalCtEnvironment {
  const UniversalCtEnvironment._();

  /// 探测一次：蓝牙可用性；平台需要运行时权限时一并检查。
  /// 探测本身失败按 transient 处理并携带原因。
  static Future<CtEnvironmentReport> probe() async {
    try {
      final state = await UniversalBle.getBluetoothAvailabilityState();
      bool? permission;
      if (BleCapabilities.requiresRuntimePermission) {
        permission = await UniversalBle.hasPermissions();
      }
      return CtEnvironmentReport(
        readiness: ctReadinessFrom(state, permissionGranted: permission),
        detail: _describe(state) +
            (permission == false ? ' + permission missing' : ''),
      );
    } catch (error) {
      return CtEnvironmentReport(
        readiness: CtBleReadiness.transient,
        detail: 'probe failed: $error',
      );
    }
  }

  /// 自检 → 修复可修项（授权、开射频）→ 复检。不抛错：结果以报告返回。
  static Future<CtEnvironmentReport> ensureReady() async {
    var report = await probe();
    if (report.readiness == CtBleReadiness.unauthorized) {
      try {
        await UniversalBle.requestPermissions();
      } catch (_) {
        // 授权被拒/失败由复检结果呈现。
      }
      report = await probe();
    }
    if (report.readiness == CtBleReadiness.poweredOff &&
        BleCapabilities.supportsBluetoothEnableApi) {
      try {
        if (await UniversalBle.enableBluetooth()) {
          report = await probe();
        }
      } catch (_) {
        // 开射频失败由原报告呈现。
      }
    }
    return report;
  }
}
