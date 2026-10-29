/// JSON 信封层（§6）：请求/响应/事件的解码与编码。
/// 解码执行 §6 的全部约束：UTF-8 无 BOM、顶层必须为 object、
/// 整数不得用浮点表达、单一值后不得有多余内容。
library;

import 'dart:convert' show jsonDecode, jsonEncode, utf8;

import 'ops.dart';

/// 信封公共基类：请求、响应或事件。
sealed class ProvEnvelope {
  const ProvEnvelope();
}

/// 请求信封 {id, op, data}。未知 op 保留原文、枚举映射为 null。
final class ProvRequest extends ProvEnvelope {
  const ProvRequest({required this.id, required this.opName, required this.data});

  final int id;
  final String opName;
  final Map<String, Object?> data;

  /// 已知 op 的枚举映射；未知 op（如设备未收录的新操作）为 null。
  ProvOp? get op => provOpFromWire(opName);
}

/// 失败响应携带的错误 {code, message}。
final class ProvError {
  const ProvError({required this.codeName, required this.message});

  /// 错误码原文（§12 九个之一；未知原文原样保留）。
  final String codeName;
  final String message;

  /// 已知错误码的枚举映射；未知错误码为 null。
  ProvErrorCode? get code => provErrorCodeFromWire(codeName);
}

/// 响应信封 {id, op, ok, data|error}，op 恒以 `.result` 结尾。
final class ProvResponse extends ProvEnvelope {
  const ProvResponse({
    required this.id,
    required this.opName,
    required this.ok,
    this.data,
    this.error,
  });

  final int id;
  final String opName;
  final bool ok;
  final Map<String, Object?>? data;
  final ProvError? error;
}

/// 异步事件信封 {seq, event, data}（v2.0 仅 protocol.error 一种事件）。
final class ProvEvent extends ProvEnvelope {
  const ProvEvent({required this.seq, required this.event, required this.data});

  final int seq;
  final String event;
  final Map<String, Object?> data;
}

/// 信封解码失败。reason 为跨端稳定标识符，与黄金向量一致：
/// bom / not_object / float_int / trailing_garbage / malformed /
/// invalid_utf8 / invalid_shape。
final class ProvEnvelopeException implements Exception {
  const ProvEnvelopeException(this.reason);

  final String reason;

  @override
  String toString() => 'ProvEnvelopeException: $reason';
}

/// 解码一个完整逻辑包的负载字节（UTF-8 JSON 信封）。
ProvEnvelope decodeEnvelope(List<int> wireBytes) {
  // BOM 必须显式拒绝：dart:convert 的 utf8.decode 会按 WHATWG 规则
  // 静默剥掉前导 BOM，故先在字节层拦截，不得依赖解码后的文本判断。
  if (wireBytes.length >= 3 &&
      wireBytes[0] == 0xEF &&
      wireBytes[1] == 0xBB &&
      wireBytes[2] == 0xBF) {
    throw const ProvEnvelopeException('bom');
  }
  final String text;
  try {
    text = utf8.decode(wireBytes);
  } on FormatException {
    throw const ProvEnvelopeException('invalid_utf8');
  }

  final start = _firstNonWhitespace(text);
  if (start < 0 || text[start] != '{') {
    // 顶层不是 object（数组、字符串、数字、字面量均属此类）。
    throw const ProvEnvelopeException('not_object');
  }
  final end = _scanObjectEnd(text, start);
  if (end < 0) {
    throw const ProvEnvelopeException('malformed');
  }
  if (text.substring(end).trim().isNotEmpty) {
    throw const ProvEnvelopeException('trailing_garbage');
  }

  final Object? value;
  try {
    value = jsonDecode(text.substring(start, end));
  } on FormatException {
    throw const ProvEnvelopeException('malformed');
  }
  if (value is! Map<String, Object?>) {
    throw const ProvEnvelopeException('not_object');
  }

  return _decodeMap(value);
}

ProvEnvelope _decodeMap(Map<String, Object?> map) {
  // 整数不得用浮点表达（§6）：先于形状检查，给出更精确的理由。
  for (final key in const ['id', 'seq']) {
    final v = map[key];
    if (v is num && v is! int) {
      throw const ProvEnvelopeException('float_int');
    }
  }

  if (map.containsKey('event')) return _decodeEvent(map);
  return _decodeRequestOrResponse(map);
}

ProvEvent _decodeEvent(Map<String, Object?> map) {
  final seq = map['seq'];
  final event = map['event'];
  final data = map['data'];
  if (seq is! int || seq < 0 || event is! String || data is! Map<String, Object?>) {
    throw const ProvEnvelopeException('invalid_shape');
  }
  return ProvEvent(seq: seq, event: event, data: data);
}

ProvEnvelope _decodeRequestOrResponse(Map<String, Object?> map) {
  final id = map['id'];
  final op = map['op'];
  if (id is! int || id < 0 || op is! String || op.isEmpty) {
    throw const ProvEnvelopeException('invalid_shape');
  }
  if (map.containsKey('ok')) return _decodeResponse(map, id, op);
  return _decodeRequest(map, id, op);
}

ProvRequest _decodeRequest(Map<String, Object?> map, int id, String op) {
  final data = map['data'];
  if (data is! Map<String, Object?>) {
    throw const ProvEnvelopeException('invalid_shape');
  }
  return ProvRequest(id: id, opName: op, data: data);
}

ProvResponse _decodeResponse(Map<String, Object?> map, int id, String op) {
  final ok = map['ok'];
  if (ok is! bool || !op.endsWith('.result')) {
    throw const ProvEnvelopeException('invalid_shape');
  }
  if (ok) {
    final data = map['data'];
    if (data != null && data is! Map<String, Object?>) {
      throw const ProvEnvelopeException('invalid_shape');
    }
    return ProvResponse(id: id, opName: op, ok: true, data: data as Map<String, Object?>?);
  }
  final error = map['error'];
  if (error is! Map<String, Object?>) {
    throw const ProvEnvelopeException('invalid_shape');
  }
  final code = error['code'];
  final message = error['message'];
  if (code is! String || message is! String) {
    throw const ProvEnvelopeException('invalid_shape');
  }
  return ProvResponse(
    id: id,
    opName: op,
    ok: false,
    error: ProvError(codeName: code, message: message),
  );
}

/// 第一个非空白字符下标；全空白返回 -1。
int _firstNonWhitespace(String s) {
  for (var i = 0; i < s.length; i++) {
    if (s[i].trim().isNotEmpty) return i;
  }
  return -1;
}

/// 从对象开括号起扫描其闭括号后一位的下标；中途字符串外的括号失配
/// 或扫描到末尾仍未闭合返回 -1。字符串内的括号与转义不影响配对。
int _scanObjectEnd(String s, int start) {
  var depth = 0;
  var inString = false;
  var escaped = false;
  for (var i = start; i < s.length; i++) {
    final c = s[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (c == r'\') {
        escaped = true;
      } else if (c == '"') {
        inString = false;
      }
      continue;
    }
    if (c == '"') {
      inString = true;
    } else if (c == '{' || c == '[') {
      depth++;
    } else if (c == '}' || c == ']') {
      depth--;
      if (depth == 0) return i + 1;
      if (depth < 0) return -1;
    }
  }
  return -1;
}

/// 编码请求信封，输出与协议示例一致的紧凑 JSON（键序 id、op、data）。
String encodeRequest({
  required int id,
  required String op,
  required Map<String, Object?> data,
}) =>
    jsonEncode({'id': id, 'op': op, 'data': data});

/// 编码响应信封。ok 为 true 携带 data（省略按空对象），
/// ok 为 false 必须携带 [error]，二者不得同时出现。
String encodeResponse({
  required int id,
  required String op,
  required bool ok,
  Map<String, Object?>? data,
  ProvError? error,
}) {
  if (ok) {
    if (error != null) {
      throw ArgumentError('error must be null when ok is true');
    }
    return jsonEncode({
      'id': id, 'op': op, 'ok': true, //
      'data': data ?? const <String, Object?>{},
    });
  }
  final err = error;
  if (err == null) {
    throw ArgumentError('error is required when ok is false');
  }
  return jsonEncode({
    'id': id, 'op': op, 'ok': false, //
    'error': {'code': err.codeName, 'message': err.message},
  });
}

/// 编码事件信封（键序 seq、event、data）。
String encodeEvent({
  required int seq,
  required String event,
  required Map<String, Object?> data,
}) =>
    jsonEncode({'seq': seq, 'event': event, 'data': data});
