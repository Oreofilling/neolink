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
    this.rejectConfigSet,
    this.supportsConfigGet = true,
  });

  @override
  final int mtu;
  final String deviceName;
  final String serialNumber;
  final String model;
  final String firmware;
  final StreamController<int> _mtuChanges = StreamController<int>.broadcast();

  /// config.set 改回指定错误码（如 FIELD_NOT_SUPPORTED）。
  final String? rejectConfigSet;

  /// false → config.get 回 UNSUPPORTED_OPERATION。
  final bool supportsConfigGet;

  /// 最近一次收到的 config.set data（断言载荷原样到达）。
  Map<String, Object?>? lastConfigSet;

  /// communication.scan 收到的请求 data（断言 section/cursor）。
  Map<String, Object?>? lastScanRequest;

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
            'stored': (envelope.data).keys.toList(),
            'apply': 'reconnect',
          },
        );
      }
    } else if (envelope.opName == ProvOp.communicationScan.wireName) {
      lastScanRequest = Map<String, Object?>.from(envelope.data);
      final cursor = envelope.data['cursor'];
      // 两页固定数据：cursor 为空第一页（more=true），否则第二页收尾。
      final firstPage = cursor == null || cursor == '';
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
            'wifi': {
              'ssid': 'Office-2.4G',
              'password': '********',
            },
            'mqtt': {
              'enable': true,
              'host': 'mqtt.example.com',
              'port': 8883,
            },
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

  test('config.set roundtrip delivers payload and reports stored sections',
      () async {
    final device = FakeCtDevice();
    final client = CtSessionClient(device);
    addTearDown(client.dispose);
    addTearDown(device.close);

    await client.open();
    final result = await client.setConfig({
      'wifi': {'ssid': 'Office-2.4G', 'password': 'example-password'},
      'mqtt': {'enable': true, 'host': 'mqtt.example.com', 'port': 8883},
    });

    expect(device.lastConfigSet, {
      'wifi': {'ssid': 'Office-2.4G', 'password': 'example-password'},
      'mqtt': {'enable': true, 'host': 'mqtt.example.com', 'port': 8883},
    });
    expect(result.stored, containsAll(['wifi', 'mqtt']));
    expect(result.apply, 'reconnect');
  });

  test('config.set rejection keeps protocol code as reason', () async {
    final device = FakeCtDevice(rejectConfigSet: 'FIELD_NOT_SUPPORTED');
    final client = CtSessionClient(device);
    addTearDown(client.dispose);
    addTearDown(device.close);

    await client.open();
    await expectLater(
      client.setConfig({
        'webhook': {'enable': true, 'url': 'https://e/h', 'secret': 's'},
      }),
      throwsA(
        isA<ProvSessionException>()
            .having((error) => error.reason, 'reason', 'field_not_supported')
            .having(
              (error) => error.message,
              'message',
              contains('FIELD_NOT_SUPPORTED'),
            ),
      ),
    );
  });

  test('communication.scan pages through cursor with extras preserved',
      () async {
    final device = FakeCtDevice();
    final client = CtSessionClient(device);
    addTearDown(client.dispose);
    addTearDown(device.close);

    await client.open();
    final first = await client.scanNetworks(section: 'wifi');

    expect(device.lastScanRequest, {'section': 'wifi'});
    expect(first.section, 'wifi');
    expect(first.items, hasLength(2));
    expect(first.items.first.networkId, 'Office-2.4G');
    expect(first.items.first.signal, -48);
    expect(first.items.first.channel, 6);
    // halow 条目的扩展字段（country）进 extras，不丢。
    expect(first.items[1].extras, containsPair('country', 'CN'));
    expect(first.more, isTrue);
    expect(first.cursor, 'page-2');

    final second = await client.scanNetworks(
      section: 'wifi',
      cursor: first.cursor,
    );
    expect(second.items, hasLength(1));
    expect(second.items.first.networkId, 'Neighbor-5G');
    expect(second.more, isFalse);
    expect(second.cursor, isEmpty);
    expect(device.lastScanRequest, {'section': 'wifi', 'cursor': 'page-2'});
  });

  test('config.get returns persisted values; unsupported resolves null',
      () async {
    final device = FakeCtDevice();
    final client = CtSessionClient(device);
    addTearDown(client.dispose);
    addTearDown(device.close);

    await client.open();
    final stored = await client.getConfig();

    expect(stored?['wifi'], {
      'ssid': 'Office-2.4G',
      'password': '********', // 密码类字段由设备决定掩码，客户端原样透传
    });
    expect(stored?['mqtt']?['port'], 8883);

    final bare = FakeCtDevice(supportsConfigGet: false);
    final bareClient = CtSessionClient(bare);
    addTearDown(bareClient.dispose);
    addTearDown(bare.close);
    await bareClient.open();
    expect(await bareClient.getConfig(), isNull);
  });
}
