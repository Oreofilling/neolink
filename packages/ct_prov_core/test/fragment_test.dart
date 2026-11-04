import 'package:ct_prov_core/ct_prov_core.dart';
import 'package:test/test.dart';
import 'package:test_vectors/test_vectors.dart' as tv;

/// 黄金向量驱动的分片层（§5）测试：重组器逐帧喂入必须还原完整逻辑包，
/// 切片器重切必须与黄金帧逐字节一致；违规输入给出与向量一致的拒绝理由。
void main() {
  ProvPacketKind kindOf(String token) => switch (token) {
        'request' => ProvPacketKind.request,
        'response' => ProvPacketKind.response,
        'event' => ProvPacketKind.event,
        _ => throw ArgumentError('unknown packet_kind token: \$token'),
      };

  test('分片常量与黄金向量包独立定义、取值一致', () {
    expect(kFragmentMagicVersion, tv.kFragmentMagicVersion);
    expect(kFragmentHeaderSize, tv.kFragmentHeaderSize);
    expect(kMaxLogicalPacketBytes, tv.kMaxLogicalPacketBytes);
    expect(kPacketKindRequest, tv.kPacketKindRequest);
    expect(kPacketKindResponse, tv.kPacketKindResponse);
    expect(kPacketKindEvent, tv.kPacketKindEvent);
    expect(kPacketKindProtocolError, tv.kPacketKindProtocolError);
  });

  test('合法向量：逐帧喂入后重组出完整逻辑包', () {
    for (final v in tv.kFragmentVectors) {
      final exp = v.expect;
      if (exp is! tv.Reassembled) continue;
      final assembler = FragmentAssembler(mtu: v.mtu);
      FeedResult? last;
      for (var i = 0; i < v.frames.length; i++) {
        last = assembler.feed(v.frames[i]);
        if (i < v.frames.length - 1) {
          expect(last, isA<Assembling>(), reason: '${v.id} 第 $i 片应处于组包中');
        }
      }
      final done = last!;
      expect(done, isA<Assembled>(), reason: '${v.id} 末片应完成组包');
      final packet = (done as Assembled).packet;
      expect(packet.kind, kindOf(exp.packetKind), reason: '${v.id} 逻辑包类型');
      expect(packet.messageId, exp.messageId, reason: '${v.id} message_id');
      expect(packet.jsonText, exp.jsonText, reason: '${v.id} 重组后 JSON 文本');
    }
  });

  test('违规向量：给出与向量一致的拒绝理由并清空缓冲', () {
    for (final v in tv.kFragmentVectors) {
      final exp = v.expect;
      if (exp is! tv.Rejected) continue;
      // incomplete 不会在喂帧中触发拒绝（末片永不到达），由专门用例覆盖。
      if (exp.reason == 'incomplete') continue;
      final assembler = FragmentAssembler(mtu: v.mtu);
      var rejected = false;
      for (final frame in v.frames) {
        final r = assembler.feed(frame);
        if (r is FeedRejected) {
          expect(r.reason, exp.reason, reason: '${v.id} 拒绝理由');
          rejected = true;
          break;
        }
      }
      expect(rejected, isTrue, reason: '${v.id} 必须被拒绝');
      expect(assembler.hasPartialAssembly, isFalse, reason: '${v.id} 拒绝后缓冲必须清空');
    }
  });

  test('缺片向量：全部帧喂完仍不完整（incomplete）', () {
    final v = tv.kFragmentVectors.firstWhere((e) => e.id == 'frag-missing-last');
    final assembler = FragmentAssembler(mtu: v.mtu);
    for (final frame in v.frames) {
      expect(assembler.feed(frame), isA<Assembling>(), reason: '${v.id} 不应完成也不应拒绝');
    }
    expect(assembler.hasPartialAssembly, isTrue, reason: '${v.id} 组包悬挂等待末片');
  });

  // 真机事故回归（NE101 + Windows，2026-11-04）：MTU 查询退守 23 的客户端，
  // 收到对端按链路实际 MTU 256 切片的 608B capabilities 响应（248/248/112 三片）。
  // 重组器不得因本地 MTU 认知不符而拒绝非末片。
  test('MTU 认知不一致：按 256 切片的多帧包，23 的重组器必须照样组起来', () {
    const jsonText = '{"id":2,"op":"communication.capabilities.get.result","ok":true,'
        '"data":{"sections":[{"name":"wifi","kind":"network","configurable":true,'
        '"scannable":true,"fields":["ssid","password"]},{"name":"cellular","kind":"network",'
        '"configurable":true,"scannable":false,"fields":["apn","username","password","pin","auth"]},'
        '{"name":"mqtt","kind":"service","configurable":true,"scannable":false,'
        '"fields":["enable","host","port"]},{"name":"webhook","kind":"service",'
        '"configurable":true,"scannable":false,"fields":["enable","url","header"]}],'
        '"current":{"network":null}}}';
    final frames = slicePacket(
      mtu: 256,
      kind: ProvPacketKind.response,
      messageId: 5,
      jsonText: jsonText,
    );
    expect(frames.length, greaterThan(1), reason: '该包必须为多片');

    final assembler = FragmentAssembler(mtu: 23);
    FeedResult? last;
    for (var i = 0; i < frames.length; i++) {
      last = assembler.feed(frames[i]);
      if (i < frames.length - 1) {
        expect(last, isA<Assembling>(), reason: '第 $i 片不得被拒绝');
      }
    }
    final done = last!;
    expect(done, isA<Assembled>(), reason: '末片必须完成组包');
    expect((done as Assembled).packet.jsonText, jsonText);
  });

  test('MTU 认知不一致（反向）：按 23 切的小片流，247 的重组器也组得起来', () {
    final frames = slicePacket(
      mtu: 23,
      kind: ProvPacketKind.request,
      messageId: 9,
      jsonText: '{"id":8,"op":"config.set","data":{"wifi":{"ssid":"CT-PROV-BENCH","password":"benchpass1"}}}',
    );
    expect(frames.length, greaterThan(1), reason: '该包必须为多片');

    final assembler = FragmentAssembler(mtu: 247);
    for (var i = 0; i < frames.length; i++) {
      final r = assembler.feed(frames[i]);
      if (i < frames.length - 1) {
        expect(r, isA<Assembling>(), reason: '第 $i 片不得被拒绝');
      }
    }
  });

  test('切片器：对合法向量重切结果与黄金帧逐字节一致', () {
    for (final v in tv.kFragmentVectors) {
      final exp = v.expect;
      if (exp is! tv.Reassembled) continue;
      final frames = slicePacket(
        mtu: v.mtu,
        kind: kindOf(exp.packetKind),
        messageId: exp.messageId,
        jsonText: exp.jsonText,
      );
      expect(frames, v.frames, reason: '${v.id} 切片与黄金帧逐字节一致');
    }
  });

  test('切片器：超过 4096 上限或 MTU 下片数超 255 时拒绝', () {
    expect(
      () => slicePacket(
        mtu: 247,
        kind: ProvPacketKind.request,
        messageId: 1,
        jsonText: 'A' * 4302,
      ),
      throwsArgumentError,
      reason: '逻辑包超过 4096 上限',
    );
    expect(
      () => slicePacket(
        mtu: 23,
        kind: ProvPacketKind.request,
        messageId: 1,
        jsonText: 'A' * 3826,
      ),
      throwsArgumentError,
      reason: 'MTU 23 下 3826B 需 256 片，超过 fragment_count 上限',
    );
  });

  test('message_id 分配器：按方向独立、取模 256 回绕', () {
    final allocator = MessageIdAllocator(start: 254);
    expect([allocator.next(), allocator.next(), allocator.next(), allocator.next()],
        [254, 255, 0, 1]);
  });
}
