// 测试替身：发现源 / GATT 设备 / 环境探测闭包注入，供控制器与页面
// 测试共用（不以下划线 test 结尾，作为普通库被导入）。
library;

import 'dart:async';

import 'package:ble_universal/ble_universal.dart';
import 'package:ct_prov_core/ct_prov_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:desktop_app/services/environment_probe.dart';

/// 可手动喂候选的假发现源，记录启停次数（广播流：重扫会再次订阅，
/// 且无监听者时 close 也能完成，与真实源行为一致）。
final class FakeSource implements DiscoverySource {
  final StreamController<DiscoveryCandidate> _controller =
      StreamController<DiscoveryCandidate>.broadcast();

  int startCount = 0;
  int stopCount = 0;

  @override
  Stream<DiscoveryCandidate> get candidates => _controller.stream;

  @override
  Future<void> start() async {
    startCount++;
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }

  void emit(DiscoveryCandidate candidate) => _controller.add(candidate);

  Future<void> close() => _controller.close();
}

/// 扮演固件侧的假设备：重组 C2D 帧，按 op 回 device.info.get 与
/// communication.capabilities.get，其余回 UNSUPPORTED_OPERATION（与
/// components/ct_prov_ble 行为对齐）。
final class FakeCtDevice implements CtGattChannel {
  FakeCtDevice({this.mtu = 23, this.rejectDeviceInfo = false});

  @override
  final int mtu;

  /// device.info.get 一律回错误（能力错误路径用）。
  final bool rejectDeviceInfo;

  @override
  Stream<int> get mtuChanges => const Stream.empty();

  final StreamController<List<int>> _d2c =
      StreamController<List<int>>.broadcast();

  @override
  Stream<List<int>> get d2cFrames => _d2c.stream;

  late final FragmentAssembler _assembler = FragmentAssembler(mtu: mtu);
  int _serverMessageId = 0;

  @override
  Future<void> writeC2d(List<int> frame) async {
    switch (_assembler.feed(frame)) {
      case Assembled(:final packet):
        _dispatch(packet.bytes);
      case FeedRejected():
        fail('fake device received a rejected fragment');
      case Assembling():
        break;
    }
  }

  void _dispatch(List<int> bytes) {
    final envelope = decodeEnvelope(bytes);
    if (envelope is! ProvRequest) return;
    final String responseJson;
    if (envelope.opName == ProvOp.deviceInfoGet.wireName) {
      if (rejectDeviceInfo) {
        responseJson = encodeResponse(
          id: envelope.id,
          op: '${ProvOp.deviceInfoGet.wireName}.result',
          ok: false,
          error: const ProvError(
            codeName: 'ERR_DEVICE_BUSY',
            message: 'device busy',
          ),
        );
      } else {
        responseJson = encodeResponse(
          id: envelope.id,
          op: '${ProvOp.deviceInfoGet.wireName}.result',
          ok: true,
          data: <String, Object?>{
            'device_name': 'NE101-AABBCC',
            'serial_number': 'NL24Q4001234',
            'model': 'NE101',
            'firmware': 'v0.3.2-dev',
            'power': ['battery'],
            'protocol_version': 1,
          },
        );
      }
    } else if (envelope.opName ==
        ProvOp.communicationCapabilitiesGet.wireName) {
      // §8 NE101 形态：无 comm 节，wifi 可扫描，当前未配置网络。
      responseJson = encodeResponse(
        id: envelope.id,
        op: '${ProvOp.communicationCapabilitiesGet.wireName}.result',
        ok: true,
        data: <String, Object?>{
          'sections': [
            {
              'name': 'wifi',
              'kind': 'network',
              'configurable': true,
              'scannable': true,
              'fields': ['ssid', 'password'],
            },
            {
              'name': 'cellular',
              'kind': 'network',
              'configurable': true,
              'fields': ['apn', 'username', 'password', 'pin', 'auth'],
            },
            {
              'name': 'mqtt',
              'kind': 'service',
              'configurable': true,
              'fields': ['enable', 'host', 'port'],
            },
          ],
          'current': {'network': null},
        },
      );
    } else {
      responseJson = encodeResponse(
        id: envelope.id,
        op: '${envelope.opName}.result',
        ok: false,
        error: const ProvError(
          codeName: 'UNSUPPORTED_OPERATION',
          message: 'operation not implemented',
        ),
      );
    }
    final frames = slicePacket(
      mtu: mtu,
      kind: ProvPacketKind.response,
      messageId: _serverMessageId++,
      jsonText: responseJson,
    );
    for (final frame in frames) {
      _d2c.add(frame);
    }
  }

  Future<void> close() => _d2c.close();
}

/// 全通道可用的探测替身（蓝牙就绪 + 一块启用的无线网卡）。
DesktopEnvironmentProbe readyProbe() => DesktopEnvironmentProbe(
  probeBle: () async => const CtEnvironmentReport(
    readiness: CtBleReadiness.ready,
    detail: 'fake ready',
  ),
  enumerateAdapters: () async =>
      '[{"Name":"Wi-Fi","Status":"Up","PhysicalMediaType":"Native 802.11"}]',
);

/// 全通道不可用的探测替身（蓝牙关 + 网卡枚举失败）。
DesktopEnvironmentProbe blockedProbe() => DesktopEnvironmentProbe(
  probeBle: () async => const CtEnvironmentReport(
    readiness: CtBleReadiness.poweredOff,
    detail: 'fake off',
  ),
  enumerateAdapters: () async => null,
);

/// 造一条可配置、空闲的候选。
DiscoveryCandidate sampleCandidate({
  String candidateId = 'dev-1',
  String? macSuffix = 'AABBCC',
  String? modelHint = 'NE101',
  bool busy = false,
}) => DiscoveryCandidate(
  candidateId: candidateId,
  macSuffix: macSuffix,
  modelHint: modelHint,
  channels: const {DiscoveryChannel.ble},
  provisionable: !busy,
  busy: busy,
  lastSeen: DateTime.now(),
  signal: -58,
);

/// 轮询等待异步条件成立（机器与流的事件投递晚于同步相位变化）。
Future<void> until(
  bool Function() condition, [
  String because = 'condition not met',
]) async {
  for (var attempt = 0; attempt < 500; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 4));
  }
  fail(because);
}
