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
