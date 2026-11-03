import 'dart:async';

import 'package:ble_adapter/ble_adapter.dart';
import 'package:ct_prov_core/ct_prov_core.dart';
import 'package:provisioning_session/provisioning_session.dart';
import 'package:test/test.dart';

/// 测试内扮演固件侧：C2D 帧喂给重组器，按 op 生成响应信封，切片后经
/// D2C 流回传 —— 与 components/ct_prov_ble 的行为对齐（device.info.get /
/// session.close / 其余 op 回 UNSUPPORTED_OPERATION）。
final class FakeCtDevice implements CtGattChannel {
  FakeCtDevice({
    this.mtu = 23,
    this.deviceName = 'NE301-AABBCC',
    this.serialNumber = 'NL24Q4001234',
    this.model = 'NE301',
    this.firmware = 'v0.3.2-dev',
    this.rejectDeviceInfo = false,
  });

  @override
  final int mtu;
  final String deviceName;
  final String serialNumber;
  final String model;
  final String firmware;
  final StreamController<int> _mtuChanges = StreamController<int>.broadcast();

  @override
  Stream<int> get mtuChanges => _mtuChanges.stream;

  // 广播流：未 open 的用例里 close() 不等监听者，避免 tearDown 挂起。
  final StreamController<List<int>> _d2c =
      StreamController<List<int>>.broadcast();

  @override
  Stream<List<int>> get d2cFrames => _d2c.stream;

  late final FragmentAssembler _assembler = FragmentAssembler(mtu: mtu);
  int _serverMessageId = 0;
  int _responseFrames = 0;

  /// §11：session.close 回包后设备主动断链。
  bool disconnected = false;

  /// device.info.get 改回 UNSUPPORTED_OPERATION（错误路径用）。
  final bool rejectDeviceInfo;

  /// 回传响应的总帧数（验证 MTU 23 下确实走多帧）。
  int get responseFrames => _responseFrames;

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
    String responseJson;
    if (envelope.opName == ProvOp.deviceInfoGet.wireName && !rejectDeviceInfo) {
      responseJson = encodeResponse(
        id: envelope.id,
        op: '${ProvOp.deviceInfoGet.wireName}.result',
        ok: true,
        data: <String, Object?>{
          'device_name': deviceName,
          'serial_number': serialNumber,
          'model': model,
          'firmware': firmware,
          'power': ['battery'],
          'protocol_version': 1,
        },
      );
    } else if (envelope.opName ==
        ProvOp.communicationCapabilitiesGet.wireName) {
      // §8 NE101 形态：无 comm 节，wifi 无 bssid，cellular 无 roaming。
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
    } else if (envelope.opName == ProvOp.sessionClose.wireName) {
      responseJson = encodeResponse(
        id: envelope.id,
        op: '${ProvOp.sessionClose.wireName}.result',
        ok: true,
      );
      disconnected = true;
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
    _responseFrames += frames.length;
    for (final frame in frames) {
      _d2c.add(frame);
    }
  }

  Future<void> close() async {
    await _mtuChanges.close();
    await _d2c.close();
  }
}

void main() {
  test('device.info.get roundtrip at MTU 23 spans multiple frames', () async {
    final device = FakeCtDevice();
    final client = CtSessionClient(device);
    addTearDown(client.dispose);
    addTearDown(device.close);

    await client.open();
    final info = await client.fetchDeviceInfo();

    expect(info.deviceName, 'NE301-AABBCC');
    expect(info.serialNumber, 'NL24Q4001234');
    expect(info.model, 'NE301');
    expect(info.firmware, 'v0.3.2-dev');
    expect(info.power, ['battery']);
    expect(info.protocolVersion, 1);
    // MTU 23 → 每帧载荷 15 字节，device.info 响应必然分片。
    expect(device.responseFrames, greaterThan(1));
    expect(device.disconnected, isFalse);
  });

  test('device.info.get roundtrip at MTU 247 fits one frame', () async {
    final device = FakeCtDevice(mtu: 247);
    final client = CtSessionClient(device);
    addTearDown(client.dispose);
    addTearDown(device.close);

    await client.open();
    final info = await client.fetchDeviceInfo();

    expect(info.deviceName, 'NE301-AABBCC');
    expect(device.responseFrames, 1);
  });

  test('capabilities roundtrip resolves sections and current network',
      () async {
    final device = FakeCtDevice();
    final client = CtSessionClient(device);
    addTearDown(client.dispose);
    addTearDown(device.close);

    await client.open();
    final capabilities = await client.fetchCapabilities();

    expect(
      capabilities.sections.map((section) => section.name).toList(),
      ['wifi', 'cellular', 'mqtt'],
    );
    expect(capabilities.sections.first.scannable, isTrue);
    expect(capabilities.sections[1].scannable, isFalse);
    expect(capabilities.currentNetwork, isNull);
  });

  test('session.close answers ok and drops the link', () async {
    final device = FakeCtDevice();
    final client = CtSessionClient(device);
    addTearDown(client.dispose);
    addTearDown(device.close);

    await client.open();
    await client.fetchDeviceInfo();
    await client.closeSession();

    expect(device.disconnected, isTrue);
  });

  test('error response surfaces as ProvSessionException', () async {
    final device = FakeCtDevice(rejectDeviceInfo: true);
    final client = CtSessionClient(device);
    addTearDown(client.dispose);
    addTearDown(device.close);

    await client.open();
    await expectLater(
      client.fetchDeviceInfo(),
      throwsA(
        isA<ProvSessionException>().having(
          (error) => error.reason,
          'reason',
          'device_info_error',
        ),
      ),
    );
  });

  test('requests before open() fail fast', () async {
    final device = FakeCtDevice();
    final client = CtSessionClient(device);
    addTearDown(client.dispose);
    addTearDown(device.close);

    await expectLater(
      client.fetchDeviceInfo(),
      throwsA(
        isA<ProvSessionException>().having(
          (error) => error.reason,
          'reason',
          'not_open',
        ),
      ),
    );
  });
}
