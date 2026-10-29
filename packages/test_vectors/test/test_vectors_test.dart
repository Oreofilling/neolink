import 'dart:convert';

import 'package:test/test.dart';
import 'package:test_vectors/test_vectors.dart';

/// 黄金向量的结构自洽性：字节布局必须与协议文档偏移表逐字段一致。
/// 解码行为测试属于 ct_prov_core（M1 第 2 步），此处只锁数据本身。
void main() {
  test('广告向量：27B 布局、AD Structure、UUID 小端、偏移表逐字节', () {
    for (final v in kAdvertisingVectors) {
      expect(v.advData.length, 27, reason: '${v.id} 长度');
      expect(v.advData.sublist(0, 3), [0x02, 0x01, 0x06], reason: '${v.id} Flags');
      expect(v.advData[3], 0x17, reason: '${v.id} Service Data Length');
      expect(v.advData[4], 0x21, reason: '${v.id} AD Type');
      expect(v.advData.sublist(5, 21), kServiceUuidLe, reason: '${v.id} UUID 小端');
      final flags = v.advData[26];
      expect((v.expect['busy'] as bool?) ?? false, (flags & 0x01) != 0, reason: '${v.id} BUSY 位');
      if (v.expect['comboViolation'] == null && v.expect['reservedBitsIgnored'] == null) {
        expect((v.expect['provisionable'] as bool?) ?? false, (flags & 0x02) != 0,
            reason: '${v.id} PROVISIONABLE 位');
      }
    }
    // 基线向量与文档 §4.2.2 示例逐字节一致
    expect(kAdvertisingVectors.first.advData, [
      0x02, 0x01, 0x06, 0x17, 0x21, //
      ...kServiceUuidLe, //
      0x01, 0x01, 0xA1, 0xB2, 0xC3, 0x02,
    ]);
  });

  test('名称向量：Scan Response 结构、字符集、长度界与临时名回退', () {
    final namePattern = RegExp(r'^[A-Z0-9-]{9,17}$');
    for (final v in kNameVectors) {
      final rsp = v.scanResponse;
      if (rsp != null) {
        expect(rsp.length, lessThanOrEqualTo(31), reason: '${v.id} 31B 上限');
        expect(rsp[1], 0x09, reason: '${v.id} AD Type');
        expect(rsp[0], 1 + rsp.length - 2, reason: '${v.id} Length=1+N');
        final name = String.fromCharCodes(rsp.sublist(2));
        if (v.expect['invalidCharset'] == true) {
          expect(namePattern.hasMatch(name), isFalse, reason: '${v.id} 应判非法字符集');
        } else {
          expect(name, v.expect['name'], reason: '${v.id} 名称回读');
          expect(namePattern.hasMatch(name), isTrue, reason: '${v.id} 字符集与长度');
        }
      } else {
        expect(v.expect['name'], isNull, reason: '${v.id} 无 Scan Response');
        expect(v.expect['tempDisplayName'], isNotNull, reason: '${v.id} 临时名');
        expect(v.expect['source'], 'derived');
      }
    }
  });

  test('META 向量：≤20B、结构与 §4.3 一致', () {
    for (final v in kMetaVectors) {
      expect(v.meta.length, lessThanOrEqualTo(20), reason: '${v.id} 20B 上限');
      expect(v.meta[0], 0x01, reason: '${v.id} protocol_version');
      expect(v.meta[2], v.meta.length - 3, reason: '${v.id} name_length');
      expect(String.fromCharCodes(v.meta.sublist(3)), v.expect['name'], reason: '${v.id} 名称');
    }
  });

  test('分片向量（合法）：头字段、片尺寸、payload_max 约定与重组总量', () {
    for (final v in kFragmentVectors) {
      final expect = v.expect;
      if (expect is! Reassembled) continue;
      final bytes = utf8.encode(expect.jsonText);
      final maxPayload = v.mtu - 3 - kFragmentHeaderSize;
      expect(v.frames.length, (bytes.length + maxPayload - 1) ~/ maxPayload, reason: '${v.id} 片数');
      var total = 0;
      for (var i = 0; i < v.frames.length; i++) {
        final f = v.frames[i];
        expect(f.length, lessThanOrEqualTo(v.mtu - 3), reason: '${v.id} 第 $i 片不超 MTU-3');
        expect(f[0], kFragmentMagicVersion, reason: '${v.id} 第 $i 片 magic');
        expect(f[3], i, reason: '${v.id} 第 $i 片 index 递增');
        expect(f[4], v.frames.length, reason: '${v.id} 第 $i 片 count');
        if (i < v.frames.length - 1) {
          expect(f.length, kFragmentHeaderSize + maxPayload, reason: '${v.id} 非末片恰好 payload_max');
        }
        total += f.length - kFragmentHeaderSize;
      }
      expect(total, bytes.length, reason: '${v.id} payload 总量');
      expect(total, lessThanOrEqualTo(kMaxLogicalPacketBytes), reason: '${v.id} 4096 上限');
      // 重组结果与期望一致
      final joined = utf8.decode(
        v.frames.expand((f) => f.sublist(kFragmentHeaderSize)).toList(growable: false),
      );
      expect(joined, expect.jsonText, reason: '${v.id} 重组回读');
    }
  });

  test('分片向量：MTU 23 极限 3825B 恰为 255 片 × 15B', () {
    final v = kFragmentVectors.firstWhere((e) => e.id == 'frag-max-3825-mtu23');
    expect(v.frames.length, 255);
    for (final f in v.frames) {
      expect(f.length, 20, reason: '5 字节头 + 15 字节负载 = MTU-3');
    }
    final expect = v.expect as Reassembled;
    expect(expect.jsonText.length, 3825);
  });

  test('分片向量（违规）：每种拒绝理由的输入确实呈现对应违规', () {
    String reasonOf(FragmentVector v) => (v.expect as Rejected).reason;
    final byReason = {for (final v in kFragmentVectors) if (v.expect is Rejected) reasonOf(v): v};
    expect(byReason.keys, containsAll([
      'bad_magic', 'unknown_packet_kind', 'out_of_order', //
      'incomplete', 'duplicate_fragment', 'header_changed', 'oversized',
    ]));

    final badMagic = byReason['bad_magic']!;
    expect(badMagic.frames.any((f) => f[0] != kFragmentMagicVersion), isTrue);

    final unknownKind = byReason['unknown_packet_kind']!;
    expect(unknownKind.frames[0][1], isNot(anyOf(0x01, 0x02, 0x03, 0x7F)));

    final outOfOrder = byReason['out_of_order']!;
    expect(outOfOrder.frames[0][3], isNot(0));

    final incomplete = byReason['incomplete']!;
    expect(incomplete.frames.length, lessThan(incomplete.frames.first[4]));

    final duplicate = byReason['duplicate_fragment']!;
    final indexes = duplicate.frames.map((f) => f[3]).toList();
    expect(indexes.toSet().length, lessThan(indexes.length));

    final headerChanged = byReason['header_changed']!;
    final counts = headerChanged.frames.map((f) => f[4]).toSet();
    expect(counts.length, greaterThan(1));

    final oversized = byReason['oversized']!;
    final total = oversized.frames.fold<int>(0, (s, f) => s + f.length - kFragmentHeaderSize);
    expect(total, greaterThan(kMaxLogicalPacketBytes));
  });

  test('信封向量：jsonText 逐条可解析且与 expect 形状一致', () {
    const knownOps = {
      'device.info.get', 'communication.capabilities.get', 'communication.scan', //
      'config.set', 'config.get', 'session.close',
    };
    const errorCodes = {
      'INVALID_MESSAGE', 'UNSUPPORTED_VERSION', 'UNSUPPORTED_OPERATION', 'INVALID_ARGUMENT', //
      'BUSY', 'SECTION_NOT_SUPPORTED', 'FIELD_NOT_SUPPORTED', 'STORAGE_FAILED', 'INTERNAL_ERROR',
    };
    final requestIds = <int>{};
    for (final v in kEnvelopeVectors) {
      if (v.invalidReason != null) {
        expect(v.expect, isNull, reason: '${v.id} 非法向量不带 expect');
        continue;
      }
      final decoded = jsonDecode(v.jsonText);
      expect(decoded, isA<Map<String, Object?>>(), reason: '${v.id} 顶层为 object');
      final e = v.expect!;
      switch (e['kind'] as String) {
        case 'request':
          final id = (decoded as Map)['id'] as int;
          expect(requestIds.add(id), isTrue, reason: '${v.id} 请求 id 唯一');
          expect(decoded['op'], e['op']);
        case 'response':
          final map = decoded as Map;
          expect(map['op'], e['op']);
          expect(map['op'] as String, endsWith('.result'));
          expect(map['ok'], e['ok']);
          if (map['ok'] == false) {
            expect(errorCodes, contains((map['error'] as Map)['code']), reason: '${v.id} 错误码 ∈ §12');
          }
        case 'event':
          expect((decoded as Map)['event'], 'protocol.error');
          expect(decoded['seq'], isA<int>());
      }
      // 请求 op：六操作之内，或专门的未知 op 向量
      if (e['kind'] == 'request') {
        expect(knownOps.contains(e['op']) || v.id == 'env-unknown-op-request', isTrue,
            reason: '${v.id} 未知 op 只允许出现在专用向量');
      }
    }
  });

  test('信封向量：四类非法输入各自成立', () {
    final byReason = {
      for (final v in kEnvelopeVectors)
        if (v.invalidReason != null) v.invalidReason!: v,
    };
    expect(byReason.keys, {'bom', 'not_object', 'float_int', 'trailing_garbage'});

    expect(byReason['bom']!.wireBytes.sublist(0, 3), [0xEF, 0xBB, 0xBF]);
    expect(() => jsonDecode(byReason['bom']!.jsonText), throwsFormatException);

    expect(jsonDecode(byReason['not_object']!.jsonText), isA<List>());

    expect(jsonDecode(byReason['float_int']!.jsonText)['id'], isA<double>());

    expect(() => jsonDecode(byReason['trailing_garbage']!.jsonText), throwsFormatException);
  });

  test('向量族数量与 id 唯一性', () {
    expect(kAdvertisingVectors.length, 8);
    expect(kNameVectors.length, 5);
    expect(kMetaVectors.length, 3);
    expect(kFragmentVectors.length, 12);
    expect(kEnvelopeVectors.length, 32);
    final ids = [
      ...kAdvertisingVectors, ...kNameVectors, ...kMetaVectors, //
      ...kFragmentVectors, ...kEnvelopeVectors,
    ].map((v) => v.id);
    expect(ids.toSet().length, ids.length, reason: '全部向量 id 唯一');
  });
}
