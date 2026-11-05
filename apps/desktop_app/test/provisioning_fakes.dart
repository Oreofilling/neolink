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

/// Fake firmware-side device: reassembles C2D frames and answers
/// device.info.get / communication.capabilities.get / config.set /
/// communication.scan / config.get; other ops answer UNSUPPORTED_OPERATION
/// (aligned with components/ct_prov_ble).
final class FakeCtDevice implements CtGattChannel {
  FakeCtDevice({
    this.mtu = 23,
    this.rejectDeviceInfo = false,
    this.capsShape = 'ne101',
    this.rejectConfigSet,
    this.supportsConfigGet = true,
    this.power = const ['battery'],
  });

  @override
  final int mtu;

  /// device.info.get always answers an error (capability failure path).
  final bool rejectDeviceInfo;

  /// Capability shape: 'ne101' (wifi/cellular/mqtt), 'ne301' (comm + wifi
  /// incl. bssid + cellular incl. roaming + readonly ethernet + mqtt +
  /// webhook incl. secret), or 'halow' (comm + scannable halow with country +
  /// fieldless cellular, i.e. a preconfigured SIM).
  final String capsShape;

  /// config.set answers this error code instead of storing (e.g.
  /// FIELD_NOT_SUPPORTED).
  final String? rejectConfigSet;

  /// false -> config.get answers UNSUPPORTED_OPERATION.
  final bool supportsConfigGet;

  /// device.info power sources; containing 'poe' drives the ethernet badge.
  final List<String> power;

  /// Last config.set data received (payload arrives intact).
  Map<String, Object?>? lastConfigSet;

  /// Last communication.scan request data (section / cursor).
  Map<String, Object?>? lastScanRequest;

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
            'power': power,
            'protocol_version': 1,
          },
        );
      }
    } else if (envelope.opName ==
        ProvOp.communicationCapabilitiesGet.wireName) {
      // §8 shapes: ne101 has no comm section, wifi without bssid, cellular
      // without roaming; ne301 carries both plus a readonly ethernet node;
      // halow carries a scannable halow node (country field) and a fieldless
      // cellular node (preconfigured SIM).
      final ne301 = capsShape == 'ne301';
      final halow = capsShape == 'halow';
      final sections = ne301
          ? <Map<String, Object?>>[
              {
                'name': 'comm',
                'kind': 'selector',
                'configurable': true,
                'scannable': false,
                'fields': ['type'],
              },
              {
                'name': 'wifi',
                'kind': 'network',
                'configurable': true,
                'scannable': true,
                'fields': ['ssid', 'password', 'bssid'],
              },
              {
                'name': 'cellular',
                'kind': 'network',
                'configurable': true,
                'scannable': false,
                'fields': ['apn', 'username', 'password', 'pin', 'auth', 'roaming'],
              },
              {
                'name': 'ethernet',
                'kind': 'network',
                'configurable': false,
                'scannable': false,
                'fields': <String>[],
              },
              {
                'name': 'mqtt',
                'kind': 'service',
                'configurable': true,
                'scannable': false,
                'fields': [
                  'enable',
                  'host',
                  'port',
                  'client_id',
                  'username',
                  'password',
                  'tls',
                  'topic',
                  'qos',
                ],
              },
              {
                'name': 'webhook',
                'kind': 'service',
                'configurable': true,
                'scannable': false,
                'fields': ['enable', 'url', 'secret', 'header'],
              },
            ]
          : halow
          ? <Map<String, Object?>>[
              {
                'name': 'comm',
                'kind': 'selector',
                'configurable': true,
                'scannable': false,
                'fields': ['type'],
              },
              {
                'name': 'halow',
                'kind': 'network',
                'configurable': true,
                'scannable': true,
                'fields': ['ssid', 'password', 'country'],
              },
              {
                'name': 'cellular',
                'kind': 'network',
                'configurable': true,
                'scannable': false,
                'fields': <String>[],
              },
            ]
          : <Map<String, Object?>>[
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
                'scannable': false,
                'fields': ['apn', 'username', 'password', 'pin', 'auth'],
              },
              {
                'name': 'mqtt',
                'kind': 'service',
                'configurable': true,
                'scannable': false,
                'fields': ['enable', 'host', 'port'],
              },
            ];
      responseJson = encodeResponse(
        id: envelope.id,
        op: '${ProvOp.communicationCapabilitiesGet.wireName}.result',
        ok: true,
        data: <String, Object?>{
          'sections': sections,
          'current': {'network': null},
        },
      );
    } else if (envelope.opName == ProvOp.sessionClose.wireName) {
      // §11: answer ok, then the device drops the link.
      responseJson = encodeResponse(
        id: envelope.id,
        op: '${ProvOp.sessionClose.wireName}.result',
        ok: true,
      );
    } else if (envelope.opName == ProvOp.configSet.wireName) {
      lastConfigSet = Map<String, Object?>.from(envelope.data);
      if (rejectConfigSet case final code?) {
        responseJson = encodeResponse(
          id: envelope.id,
          op: '${ProvOp.configSet.wireName}.result',
          ok: false,
          error: ProvError(codeName: code, message: 'field not in fields'),
        );
      } else {
        responseJson = encodeResponse(
          id: envelope.id,
          op: '${ProvOp.configSet.wireName}.result',
          ok: true,
          data: <String, Object?>{
            'stored': envelope.data.keys.toList(),
            'apply': 'reconnect',
          },
        );
      }
    } else if (envelope.opName == ProvOp.communicationScan.wireName) {
      lastScanRequest = Map<String, Object?>.from(envelope.data);
      // Two fixed pages: empty cursor -> page 1 (more), else page 2 (end).
      final firstPage = (envelope.data['cursor'] ?? '') == '';
      responseJson = encodeResponse(
        id: envelope.id,
        op: '${ProvOp.communicationScan.wireName}.result',
        ok: true,
        data: <String, Object?>{
          'section': envelope.data['section'],
          'items': firstPage
              ? [
                  {
                    'network_id': 'Office-2.4G',
                    'display_name': 'Office-2.4G',
                    'signal': -48,
                    'channel': 6,
                  },
                  {
                    'network_id': 'CT-HaLow',
                    'display_name': 'CT-HaLow',
                    'signal': -71,
                    'country': 'CN',
                  },
                ]
              : [
                  {
                    'network_id': 'Neighbor-5G',
                    'display_name': 'Neighbor-5G',
                    'signal': -82,
                    'channel': 36,
                  },
                ],
          'more': firstPage,
          'cursor': firstPage ? 'page-2' : '',
        },
      );
    } else if (envelope.opName == 'config.get') {
      if (!supportsConfigGet) {
        responseJson = encodeResponse(
          id: envelope.id,
          op: 'config.get.result',
          ok: false,
          error: const ProvError(
            codeName: 'UNSUPPORTED_OPERATION',
            message: 'config.get not supported',
          ),
        );
      } else {
        responseJson = encodeResponse(
          id: envelope.id,
          op: 'config.get.result',
          ok: true,
          data: <String, Object?>{
            'wifi': {'ssid': 'Office-2.4G', 'password': '********'},
            'mqtt': {'enable': true, 'host': 'mqtt.example.com', 'port': 8883},
          },
        );
      }
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

/// FakeCtDevice 加手动闸：armGate 后的下一批上行帧等 openGate 才放行，
/// 用于把 config.set 摁在途（配合断连测试的 delivering 场景）。
final class GatedFakeCtDevice extends FakeCtDevice {
  Completer<void>? _gate;

  void armGate() => _gate = Completer<void>();
  void openGate() => _gate?.complete();

  @override
  Future<void> writeC2d(List<int> frame) async {
    final gate = _gate;
    if (gate != null && !gate.isCompleted) await gate.future;
    await super.writeC2d(frame);
  }
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

/// 造一条可配置、空闲的候选（[seen] 回溯 lastSeen，供时效标注用例）。
DiscoveryCandidate sampleCandidate({
  String candidateId = 'dev-1',
  String? macSuffix = 'AABBCC',
  String? modelHint = 'NE101',
  bool busy = false,
  DateTime? seen,
}) => DiscoveryCandidate(
  candidateId: candidateId,
  macSuffix: macSuffix,
  modelHint: modelHint,
  channels: const {DiscoveryChannel.ble},
  provisionable: !busy,
  busy: busy,
  lastSeen: seen ?? DateTime.now(),
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
