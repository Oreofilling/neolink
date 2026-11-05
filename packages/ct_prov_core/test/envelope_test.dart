import 'dart:convert';

import 'package:ct_prov_core/ct_prov_core.dart';
import 'package:test/test.dart';
import 'package:test_vectors/test_vectors.dart' as tv;

/// 黄金向量驱动的信封层（§6）测试：解码形状与 expect 一致、
/// 解码后重新编码与原文逐字节一致、四类非法输入给出一致理由。
void main() {
  String reencode(ProvEnvelope envelope) => switch (envelope) {
        ProvRequest r => encodeRequest(id: r.id, op: r.opName, data: r.data),
        ProvResponse r => r.ok
            ? encodeResponse(
                id: r.id, op: r.opName, ok: true, data: r.data ?? {})
            : encodeResponse(
                id: r.id, op: r.opName, ok: false, error: r.error!),
        ProvEvent e => encodeEvent(seq: e.seq, event: e.event, data: e.data),
      };

  test('合法信封：解码结果与 expect 形状一致', () {
    for (final v in tv.kEnvelopeVectors) {
      if (v.invalidReason != null) continue;
      final e = v.expect!;
      switch (decodeEnvelope(v.wireBytes)) {
        case ProvRequest r:
          expect(e['kind'], 'request', reason: '${v.id} 种类');
          expect(r.id, e['id'], reason: '${v.id} id');
          expect(r.opName, e['op'], reason: '${v.id} op');
          expect(r.data, e['data'], reason: '${v.id} data');
          if (v.id == 'env-unknown-op-request') {
            expect(r.op, isNull, reason: '${v.id} 未知 op 映射为 null');
          } else {
            expect(r.op, isNotNull, reason: '${v.id} 已知 op 应映射到枚举');
          }
        case ProvResponse r:
          expect(e['kind'], 'response', reason: '${v.id} 种类');
          expect(r.id, e['id'], reason: '${v.id} id');
          expect(r.opName, e['op'], reason: '${v.id} op');
          expect(r.ok, e['ok'], reason: '${v.id} ok');
          if (r.ok) {
            // 个别向量（如无法关联的响应）的 expect 省略 data 键，按空对象比较。
            expect(r.data, e['data'] ?? const <String, Object?>{},
                reason: '${v.id} data');
          } else {
            final wireError = e['error'] as Map;
            expect(r.error, isNotNull, reason: '${v.id} 失败必带 error');
            expect(r.error!.codeName, wireError['code'],
                reason: '${v.id} 错误码原文');
            expect(r.error!.code!.wireName, wireError['code'],
                reason: '${v.id} 错误码枚举映射');
          }
        case ProvEvent ev:
          expect(e['kind'], 'event', reason: '${v.id} 种类');
          expect(ev.seq, e['seq'], reason: '${v.id} seq');
          expect(ev.event, e['event'], reason: '${v.id} event');
          expect(ev.data, e['data'], reason: '${v.id} data');
      }
    }
  });

  test('合法信封：解码后重新编码与原文逐字节一致', () {
    for (final v in tv.kEnvelopeVectors) {
      if (v.invalidReason != null) continue;
      expect(reencode(decodeEnvelope(v.wireBytes)), v.jsonText,
          reason: '${v.id} 编码往返逐字节一致');
    }
  });

  test('非法信封：异常理由与向量标注一致', () {
    for (final v in tv.kEnvelopeVectors) {
      if (v.invalidReason == null) continue;
      expect(
          () => decodeEnvelope(v.wireBytes),
          throwsA(isA<ProvEnvelopeException>()
              .having((err) => err.reason, 'reason', v.invalidReason)),
          reason: '${v.id} 非法理由');
    }
  });

  test('非法信封补充：截断、缺字段与响应 op 后缀', () {
    // 顶层对象未闭合 → malformed
    expect(
      () => decodeEnvelope(utf8.encode('{"id":1,"op":')),
      throwsA(isA<ProvEnvelopeException>()
          .having((err) => err.reason, 'reason', 'malformed')),
    );
    // 请求缺 data → invalid_shape
    expect(
      () => decodeEnvelope(utf8.encode('{"id":1,"op":"device.info.get"}')),
      throwsA(isA<ProvEnvelopeException>()
          .having((err) => err.reason, 'reason', 'invalid_shape')),
    );
    // 响应 op 不带 .result 后缀 → invalid_shape
    expect(
      () => decodeEnvelope(
          utf8.encode('{"id":1,"op":"device.info.get","ok":true,"data":{}}')),
      throwsA(isA<ProvEnvelopeException>()
          .having((err) => err.reason, 'reason', 'invalid_shape')),
    );
  });

  test('错误码枚举：九个 wireName 与协议 §12 一致', () {
    const wireNames = {
      'INVALID_MESSAGE',
      'UNSUPPORTED_VERSION',
      'UNSUPPORTED_OPERATION',
      'INVALID_ARGUMENT',
      'BUSY',
      'SECTION_NOT_SUPPORTED',
      'FIELD_NOT_SUPPORTED',
      'STORAGE_FAILED',
      'INTERNAL_ERROR',
    };
    expect(ProvErrorCode.values.map((c) => c.wireName).toSet(), wireNames);
    expect(provErrorCodeFromWire('BUSY'), ProvErrorCode.busy);
    expect(provErrorCodeFromWire('NO_SUCH_CODE'), isNull);
  });
}
