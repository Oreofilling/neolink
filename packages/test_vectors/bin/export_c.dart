/// 把黄金向量导出为 C 头文件（固件侧 ct_prov 组件的测试数据源）。
/// 单一事实来源在本包：修改向量后运行
/// `dart run bin/export_c.dart <输出路径>` 重新生成，产物提交进固件仓库。
library;

import 'dart:io';
import 'dart:convert';

import 'package:test_vectors/test_vectors.dart';

/// JSON 文本转 C 字符串字面量：可打印 ASCII 原样，引号/反斜杠转义，
/// 其余字节（含 UTF-8 中文与控制符）一律 \NNN 八进制，避免十六进制连字歧义。
String _cString(String text) {
  final bytes = utf8.encode(text);
  final sb = StringBuffer();
  for (final b in bytes) {
    if (b == 0x22 || b == 0x5C) {
      sb.write('\\${String.fromCharCode(b)}');
    } else if (b >= 0x20 && b < 0x7F) {
      sb.write(String.fromCharCode(b));
    } else {
      sb.write('\\${b.toRadixString(8).padLeft(3, '0')}');
    }
  }
  return sb.toString();
}

/// 向量 id 转 C 标识符：非字母数字一律换下划线（连字符在 C 里非法）。
/// id 字符串本身原样保留在 .id 字段，仅标识符做转换。
String _cIdent(String id) => id.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');

/// 字节数组转 C 初始化器（每行 12 字节）。
String _cBytes(List<int> bytes) => bytes.isEmpty
    ? ''
    : bytes
        .asMap()
        .entries
        .fold('', (acc, e) => '$acc${e.key % 12 == 0 ? '\n    ' : ''}0x${e.value.toRadixString(16).padLeft(2, '0').toUpperCase()},')
        .replaceFirst(RegExp(r',$'), '');

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('用法: dart run bin/export_c.dart <输出路径>');
    exitCode = 2;
    return;
  }

  final out = StringBuffer('''
// 由 neolink packages/test_vectors 的 bin/export_c.dart 生成 —— 请勿手改。
// 黄金向量是跨端单一事实来源（CT_PROV_PROTOCOL.md §15），修改请先改 Dart 侧再导出。
#ifndef CT_PROV_VECTORS_H
#define CT_PROV_VECTORS_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    size_t len;
    const uint8_t *data;
} ct_prov_bytes_t;

typedef struct {
    const char *id;
    unsigned mtu;
    size_t frame_count;
    const ct_prov_bytes_t *frames;
    int rejected;            // 1 = 期望拒绝
    const char *reason;      // 拒绝时为黄金 token，否则空串
    const char *packet_kind; // 重组成功时为 request/response/event
    unsigned message_id;
    const char *json_text;   // 重组成功时的负载原文，否则空串
} ct_prov_fragment_vector_t;

''');

  // ---- 分片族 ----
  for (final v in kFragmentVectors) {
    final expect = v.expect;
    final rejected = expect is Rejected;
    final kind = expect is Reassembled ? expect.packetKind : '';
    final messageId = expect is Reassembled ? expect.messageId : 0;
    final jsonText = expect is Reassembled ? expect.jsonText : '';
    // rejected 为局部 bool，sealed 类型提升会流经它，无需显式 cast。
    final reason = rejected ? expect.reason : '';
    for (var i = 0; i < v.frames.length; i++) {
      out.writeln('static const uint8_t k_${_cIdent(v.id)}_f$i[${v.frames[i].length}] = {${_cBytes(v.frames[i])}\n};');
    }
    out.writeln(
        'static const ct_prov_bytes_t k_${_cIdent(v.id)}_frames[${v.frames.length}] = {');
    for (var i = 0; i < v.frames.length; i++) {
      out.writeln('    {.len = ${v.frames[i].length}, .data = k_${_cIdent(v.id)}_f$i},');
    }
    out.writeln('};');
    out.writeln('''
// ${v.description}
static const ct_prov_fragment_vector_t k_${_cIdent(v.id)} = {
    .id = "${v.id}",
    .mtu = ${v.mtu},
    .frame_count = ${v.frames.length},
    .frames = k_${_cIdent(v.id)}_frames,
    .rejected = ${rejected ? 1 : 0},
    .reason = "$reason",
    .packet_kind = "$kind",
    .message_id = $messageId,
    .json_text = "${_cString(jsonText)}",
};
''');
  }
  out.writeln('''
static const ct_prov_fragment_vector_t
    k_ct_prov_fragment_vectors[] = {''');
  for (final v in kFragmentVectors) {
    out.writeln('    k_${_cIdent(v.id)},');
  }
  out.writeln('};');
  out.writeln('#define CT_PROV_FRAGMENT_VECTOR_COUNT '
      '${kFragmentVectors.length}');

  // ---- 信封族 ----
  out.writeln('''
typedef struct {
    const char *id;
    const char *json_text;   // 原文字节（八进制转义的 UTF-8）
    int valid;               // 1 = 可解码；0 = 非法（invalid_reason 给出原因）
    const char *invalid_reason;
} ct_prov_envelope_vector_t;
''');
  for (final v in kEnvelopeVectors) {
    final invalid = v.invalidReason != null;
    out.writeln('''
// ${v.description}
static const ct_prov_envelope_vector_t k_${_cIdent(v.id)} = {
    .id = "${v.id}",
    .json_text = "${_cString(v.jsonText)}",
    .valid = ${invalid ? 0 : 1},
    .invalid_reason = "${invalid ? v.invalidReason : ''}",
};
''');
  }
  out.writeln('static const ct_prov_envelope_vector_t k_ct_prov_envelope_vectors[] = {');
  for (final v in kEnvelopeVectors) {
    out.writeln('    k_${_cIdent(v.id)},');
  }
  out.writeln('};');
  out.writeln('#define CT_PROV_ENVELOPE_VECTOR_COUNT ${kEnvelopeVectors.length}');

  out.writeln('''
#ifdef __cplusplus
}
#endif

#endif // CT_PROV_VECTORS_H
''');

  File(args[0]).writeAsString(out.toString());
  stderr.writeln('已生成 ${kFragmentVectors.length} 条分片向量、'
      '${kEnvelopeVectors.length} 条信封向量 → ${args[0]}');
}
