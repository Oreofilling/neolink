import 'dart:async';

import 'package:ble_adapter/ble_adapter.dart';
import 'package:ct_prov_core/ct_prov_core.dart';
import 'package:test/test.dart';
import 'package:test_vectors/test_vectors.dart' as tv;

/// GATT 传输层测试：分片泵、请求关联、事件分发与错误面。
/// 用内存假通道做环回：写入被记录，指示帧由测试注入。
void main() {
  /// 按协议文档示例构造 device.info.get 请求。
  ProvRequest deviceInfoRequest() => const ProvRequest(
    id: 1,
    opName: 'device.info.get',
    data: <String, Object?>{},
  );

  /// 取向量 JSON 原文。
  String jsonOf(String id) =>
      tv.kEnvelopeVectors.firstWhere((v) => v.id == id).jsonText;

  /// 把 JSON 原文按 MTU 切成指示帧序列（模拟设备侧发送）。
  List<List<int>> framesOf(
    String jsonText, {
    int mtu = 23,
    required int messageId,
  }) => slicePacket(
    mtu: mtu,
    kind: ProvPacketKind.response,
    messageId: messageId,
    jsonText: jsonText,
  );

  test('发送请求：写出帧与切片器输出逐字节一致，message_id 递增', () async {
    final channel = FakeChannel();
    final transport = CtProvGattTransport(channel)..start();
    final first = transport.sendRequest(deviceInfoRequest());
    channel.respond(
      framesOf(jsonOf('env-resp-device-info-ne101'), messageId: 0),
    );
    await first;
    final second = transport.sendRequest(
      const ProvRequest(
        id: 2,
        opName: 'communication.capabilities.get',
        data: {},
      ),
    );
    channel.respond(
      framesOf(jsonOf('env-resp-capabilities-ne301'), messageId: 1),
    );
    await second;

    // 信封文本与协议示例逐字节一致（黄金锚点），再按切片器比对写出帧。
    expect(
      encodeRequest(id: 1, op: 'device.info.get', data: {}),
      jsonOf('env-req-device-info'),
    );
    final req1 = slicePacket(
      mtu: 23,
      kind: ProvPacketKind.request,
      messageId: 0,
      jsonText: jsonOf('env-req-device-info'),
    );
    final req2 = slicePacket(
      mtu: 23,
      kind: ProvPacketKind.request,
      messageId: 1,
      jsonText: encodeRequest(
        id: 2,
        op: 'communication.capabilities.get',
        data: {},
      ),
    );
    expect(req1, hasLength(3), reason: '41B 请求在 MTU 23 下切 3 片');
    expect(req2, hasLength(4), reason: '56B 请求切 4 片');
    expect(channel.writes, [...req1, ...req2], reason: '写出帧与切片器输出逐字节一致');
  });

  test('close 中止在途请求：无未处理错误，后续发送直接拒绝', () async {
    final channel = FakeChannel();
    final transport = CtProvGattTransport(channel)..start();
    final future = transport.sendRequest(deviceInfoRequest());
    // 挂好期望再 close：close 发生在写入完成、响应未回之间，在途
    // completer 一度没有监听者，错误投递不得升级为未处理异步错误
    // （链接断开是常态路径）。
    final outcome = expectLater(future, throwsStateError);
    await transport.close();
    await outcome;
    // 关闭后的新请求立即失败，不再写帧。
    final writesAfterClose = channel.writes.length;
    await expectLater(
      transport.sendRequest(deviceInfoRequest()),
      throwsStateError,
    );
    expect(channel.writes.length, writesAfterClose);
  });

  test('多片响应：重组后按信封 id 关联完成请求', () async {
    final channel = FakeChannel();
    final transport = CtProvGattTransport(channel)..start();
    final future = transport.sendRequest(deviceInfoRequest());
    channel.respond(
      framesOf(jsonOf('env-resp-device-info-ne101'), messageId: 4),
    );
    final resp = await future;
    expect(resp.ok, isTrue);
    expect(resp.id, 1);
    expect((resp.data!['model'] as String), 'NE101');
  });

  test('无法关联的响应 id：必须忽略且不干扰在途请求', () async {
    final channel = FakeChannel();
    final transport = CtProvGattTransport(channel)..start();
    final future = transport.sendRequest(deviceInfoRequest());
    channel.respond(
      framesOf(jsonOf('env-unmatched-response-id'), messageId: 2),
    );
    // 给事件循环一个节拍，确认未完成也未抛错
    await Future<void>.delayed(Duration.zero);
    expect(transport.ignoredResponses, 1, reason: '未知 id 计入忽略');
    channel.respond(
      framesOf(jsonOf('env-resp-device-info-ne101'), messageId: 3),
    );
    final resp = await future;
    expect(resp.id, 1);
  });

  test('protocol.error 事件：走事件流，不触碰请求关联', () async {
    final channel = FakeChannel();
    final transport = CtProvGattTransport(channel)..start();
    final events = <ProvEvent>[];
    transport.events.listen(events.add);
    final future = transport.sendRequest(deviceInfoRequest());
    channel.respond(
      framesOf('{"seq":8,"event":"protocol.error","data":{}}', messageId: 5),
    );
    await Future<void>.delayed(Duration.zero);
    expect(events, hasLength(1));
    expect(events.first.seq, 8);
    expect(events.first.event, 'protocol.error');
    channel.respond(
      framesOf(jsonOf('env-resp-device-info-ne101'), messageId: 6),
    );
    await future;
  });

  test('分片违规：报错误流，请求保持挂起', () async {
    final channel = FakeChannel();
    final transport = CtProvGattTransport(channel)..start();
    final errors = <String>[];
    transport.frameErrors.listen(errors.add);
    final future = transport.sendRequest(deviceInfoRequest());
    final bad = framesOf(jsonOf('env-resp-device-info-ne101'), messageId: 7);
    channel.respond([
      ...bad.take(1),
      [0xC0, ...bad[1].sublist(1)],
      ...bad.skip(2),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(errors, contains('bad_magic'), reason: '坏 magic 必须上报');
    channel.respond(
      framesOf(jsonOf('env-resp-device-info-ne101'), messageId: 8),
    );
    await future;
  });

  test('信封解码失败：报 envelope: 前缀错误，请求保持挂起', () async {
    final channel = FakeChannel();
    final transport = CtProvGattTransport(channel)..start();
    final errors = <String>[];
    transport.frameErrors.listen(errors.add);
    final future = transport.sendRequest(deviceInfoRequest());
    channel.respond(framesOf(jsonOf('env-invalid-bom'), messageId: 9));
    await Future<void>.delayed(Duration.zero);
    expect(errors, contains('envelope:bom'));
    channel.respond(
      framesOf(jsonOf('env-resp-device-info-ne101'), messageId: 10),
    );
    await future;
  });

  test('超时：无响应抛 TimeoutException 并清理挂起表', () async {
    final channel = FakeChannel();
    final transport = CtProvGattTransport(channel)..start();
    await expectLater(
      transport.sendRequest(
        deviceInfoRequest(),
        timeout: const Duration(milliseconds: 10),
      ),
      throwsA(isA<TimeoutException>()),
    );
    // 同一 id 可立即重发（挂起表已清理）
    final retry = transport.sendRequest(deviceInfoRequest());
    channel.respond(
      framesOf(jsonOf('env-resp-device-info-ne101'), messageId: 11),
    );
    await retry;
  });

  test('写入失败：清理挂起表，后续可重发同一 id', () async {
    final channel = FakeChannel();
    final transport = CtProvGattTransport(channel)..start();
    final writeError = StateError('link dropped');
    channel.writeError = writeError;

    await expectLater(
      transport.sendRequest(deviceInfoRequest()),
      throwsA(same(writeError)),
    );

    channel.writeError = null;
    final retry = transport.sendRequest(deviceInfoRequest());
    channel.respond(
      framesOf(jsonOf('env-resp-device-info-ne101'), messageId: 11),
    );
    final response = await retry;
    expect(response.id, 1);
  });

  test('在途 id 重复发送：直接拒绝', () async {
    final channel = FakeChannel();
    final transport = CtProvGattTransport(channel)..start();
    final first = transport.sendRequest(deviceInfoRequest());
    expect(
      () => transport.sendRequest(deviceInfoRequest()),
      throwsArgumentError,
      reason: '同 id 在途时不得重复发送',
    );
    channel.respond(
      framesOf(jsonOf('env-resp-device-info-ne101'), messageId: 12),
    );
    await first;
  });

  test('MTU 协商：切换后按新 MTU 切片并重建重组器', () async {
    final channel = FakeChannel();
    final transport = CtProvGattTransport(channel)..start();
    channel.negotiateMtu(61);
    await Future<void>.delayed(Duration.zero);
    final future = transport.sendRequest(
      const ProvRequest(
        id: 2,
        opName: 'communication.capabilities.get',
        data: {},
      ),
    );
    // MTU 61：payload_max=53，56B 请求切 2 片（53+3），帧总长 5+53=58 ≤ MTU-3；
    // 829B 能力响应仍需 16 片，重组不受切片变大的影响。
    final respFrames = framesOf(
      jsonOf('env-resp-capabilities-ne301'),
      mtu: 61,
      messageId: 20,
    );
    expect(
      respFrames,
      hasLength(16),
      reason: '829B 响应在 payload_max 53 下切 16 片',
    );
    expect(respFrames.first.length, 58, reason: '首帧 5+53=58 不超 MTU-3');
    channel.respond(respFrames);
    await future;
    final expectedFrames = slicePacket(
      mtu: 61,
      kind: ProvPacketKind.request,
      messageId: 0,
      jsonText: encodeRequest(
        id: 2,
        op: 'communication.capabilities.get',
        data: {},
      ),
    );
    expect(channel.writes, expectedFrames, reason: '请求帧与切片器在 MTU 61 下逐字节一致');
    expect(channel.writes.first.length, 58, reason: '请求首帧 5+53');
  });
}

/// 内存假通道：记录 C2D 写入，d2cFrames 由 respond() 注入。
class FakeChannel implements CtGattChannel {
  final List<List<int>> writes = [];
  final _d2c = StreamController<List<int>>.broadcast();
  final _mtuChanges = StreamController<int>.broadcast();
  Object? writeError;

  int _mtu = 23;
  @override
  int get mtu => _mtu;

  @override
  Stream<int> get mtuChanges => _mtuChanges.stream;

  @override
  Stream<List<int>> get d2cFrames => _d2c.stream;

  @override
  Future<void> writeC2d(List<int> frame) async {
    final error = writeError;
    if (error != null) throw error;
    writes.add(List<int>.of(frame));
  }

  /// 注入一串指示帧（模拟设备侧 D2C）。
  void respond(Iterable<List<int>> frames) {
    for (final f in frames) {
      _d2c.add(f);
    }
  }

  /// 触发 MTU 协商结果。
  void negotiateMtu(int value) {
    _mtu = value;
    _mtuChanges.add(value);
  }
}
