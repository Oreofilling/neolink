/// GATT 分片层（§5）：发送侧切片器与 message_id 分配器。
/// 非末片恰好装满 payload_max，与黄金向量的切片逐字节一致。
library;

import 'dart:convert' show utf8;

import 'fragment.dart';

/// 把一个逻辑包按 MTU 切片为帧序列（含 5 字节分片头，按序发出即可）。
///
/// 抛 [ArgumentError]：负载超过 4096 上限，或在给定 MTU 下片数超过
/// fragment_count 上限 255（MTU 23 下最大 3825 字节）。
List<List<int>> slicePacket({
  required int mtu,
  required ProvPacketKind kind,
  required int messageId,
  required String jsonText,
}) {
  final payloadMax = mtu - 3 - kFragmentHeaderSize;
  if (payloadMax < 1) {
    throw ArgumentError('mtu too small: $mtu (payload_max must be at least 1)');
  }
  final bytes = utf8.encode(jsonText);
  if (bytes.isEmpty) {
    throw ArgumentError('packet payload must not be empty');
  }
  if (bytes.length > kMaxLogicalPacketBytes) {
    throw ArgumentError('packet exceeds limit: ${bytes.length} > $kMaxLogicalPacketBytes');
  }
  final count = (bytes.length + payloadMax - 1) ~/ payloadMax;
  if (count > 255) {
    throw ArgumentError('needs $count fragments at MTU $mtu, over fragment_count limit 255');
  }
  final frames = <List<int>>[
    for (var i = 0; i < bytes.length; i += payloadMax)
      [
        kFragmentMagicVersion, kind.wireByte, messageId % 256, //
        i ~/ payloadMax, count, ...bytes.sublist(i, i + payloadMax > bytes.length ? bytes.length : i + payloadMax),
      ],
  ];
  return frames;
}

/// 分片层 message_id 分配器（每方向一个，取模 256 回绕递增）。
final class MessageIdAllocator {
  MessageIdAllocator({int start = 0}) : _next = start % 256;

  int _next;

  /// 取出下一个 message_id（0..255 循环）。
  int next() {
    final id = _next;
    _next = (_next + 1) % 256;
    return id;
  }
}
