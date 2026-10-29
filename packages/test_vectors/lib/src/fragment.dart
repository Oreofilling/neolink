/// GATT 分片族向量：§5 的 5 字节分片头、组包规则与违规输入。
/// `fragment_payload_max = ATT_MTU - 3 - 5`；v2.0 分片层无 CRC。
library;

import 'dart:convert';
import 'dart:math' as math;

/// 分片重组的期望结果。
sealed class FragmentExpect {
  const FragmentExpect();
}

/// 重组成功：得到一个完整逻辑包（JSON 文本）。
final class Reassembled extends FragmentExpect {
  const Reassembled({required this.packetKind, required this.messageId, required this.jsonText});

  /// 逻辑包类型：请求 / 响应 / 事件（字段值为 §5 packet_kind 对应的协议 token）。
  final String packetKind;
  final int messageId;
  final String jsonText;
}

/// 重组必须失败并丢弃当前组包缓冲。reason 对应 §5 的终止条件。
final class Rejected extends FragmentExpect {
  const Rejected(this.reason);

  /// 拒绝理由：坏 magic / 未知类型 / 乱序 / 缺片 / 重复片 / 头部字段变化 /
  /// 超过 4096 上限 / 组包不完整。字段值为跨端稳定的标识符，见各向量 expect。
  final String reason;
}

/// 分片向量：frames 为按到达顺序排列的 ATT 写入/指示负载（含 5B 头）。
final class FragmentVector {
  const FragmentVector({
    required this.id,
    required this.description,
    required this.mtu,
    required this.frames,
    required this.expect,
  });

  final String id;
  final String description;
  final int mtu;
  final List<List<int>> frames;
  final FragmentExpect expect;
}

/// 分片头常量（§5）。
const int kFragmentMagicVersion = 0xC1;
const int kPacketKindRequest = 0x01;
const int kPacketKindResponse = 0x02;
const int kPacketKindEvent = 0x03;
const int kPacketKindProtocolError = 0x7F;
const int kFragmentHeaderSize = 5;
const int kMaxLogicalPacketBytes = 4096;

/// 把 JSON 文本按 MTU 切片为分片序列（非末片恰好 payload_max）。
List<List<int>> _frames({required int mtu, required int kind, required int messageId, required String jsonText}) {
  final bytes = utf8.encode(jsonText);
  final maxPayload = mtu - 3 - kFragmentHeaderSize;
  final frames = <List<int>>[];
  for (var i = 0; i < bytes.length; i += maxPayload) {
    final end = math.min(i + maxPayload, bytes.length);
    frames.add([
      kFragmentMagicVersion, kind, messageId, frames.length, //
      (bytes.length + maxPayload - 1) ~/ maxPayload, ...bytes.sublist(i, end),
    ]);
  }
  return frames;
}

/// 构造总字节数恰为 [total] 的合法 config.set JSON（ASCII，填充 'A'）。
String _exactSizedJson(int total) {
  const head = '{"id":20,"op":"config.set","data":{"wifi":{"ssid":"';
  const tail = '"}}}';
  final pad = total - head.length - tail.length;
  assert(pad >= 1, 'total 过小：$total');
  return head + 'A' * pad + tail;
}

const String _deviceInfoReq = '{"id":1,"op":"device.info.get","data":{}}';
const String _protocolErrorEvent =
    '{"seq":2,"event":"protocol.error","data":{"code":"INVALID_MESSAGE","message":"fragment reassembly timeout"}}';

final List<FragmentVector> kFragmentVectors = [
  FragmentVector(
    id: 'frag-single-large-mtu',
    description: '单分片：MTU 61（payload_max 53）下 41B 请求一片装下',
    mtu: 61,
    frames: _frames(mtu: 61, kind: kPacketKindRequest, messageId: 7, jsonText: _deviceInfoReq),
    expect: Reassembled(packetKind: 'request', messageId: 7, jsonText: _deviceInfoReq),
  ),
  FragmentVector(
    id: 'frag-multi-mtu23',
    description: 'MTU 23 基线：41B 请求切为 15/15/11 三片',
    mtu: 23,
    frames: _frames(mtu: 23, kind: kPacketKindRequest, messageId: 7, jsonText: _deviceInfoReq),
    expect: Reassembled(packetKind: 'request', messageId: 7, jsonText: _deviceInfoReq),
  ),
  FragmentVector(
    id: 'frag-max-3825-mtu23',
    description: 'MTU 23 最大合法消息：255 片 × 15B = 3825B（fragment_count 上限可达的极限）',
    mtu: 23,
    frames: _frames(mtu: 23, kind: kPacketKindRequest, messageId: 9, jsonText: _exactSizedJson(3825)),
    expect: Reassembled(packetKind: 'request', messageId: 9, jsonText: _exactSizedJson(3825)),
  ),
  FragmentVector(
    id: 'frag-oversize-4302',
    description: '协议违规发送方：MTU 247 下 18 片 × 239B = 4302B > 4096 上限，接收端必须拒绝',
    mtu: 247,
    frames: _frames(mtu: 247, kind: kPacketKindRequest, messageId: 3, jsonText: _exactSizedJson(4302)),
    expect: const Rejected('oversized'),
  ),
  FragmentVector(
    id: 'frag-response-kind',
    description: 'RESPONSE 逻辑包多片重组（MTU 23）',
    mtu: 23,
    frames: _frames(
      mtu: 23,
      kind: kPacketKindResponse,
      messageId: 4,
      jsonText: '{"id":1,"op":"device.info.result","ok":true,"data":{"device_name":"NE101-A1B2C3",'
          '"serial_number":"NE101202610270001","model":"NE101","firmware":"1.8.0",'
          '"power":["battery"],"protocol_version":1}}',
    ),
    expect: Reassembled(
      packetKind: 'response',
      messageId: 4,
      jsonText: '{"id":1,"op":"device.info.result","ok":true,"data":{"device_name":"NE101-A1B2C3",'
          '"serial_number":"NE101202610270001","model":"NE101","firmware":"1.8.0",'
          '"power":["battery"],"protocol_version":1}}',
    ),
  ),
  FragmentVector(
    id: 'frag-event-kind',
    description: 'EVENT 单片：protocol.error 异步事件（MTU 131）',
    mtu: 131,
    frames: _frames(mtu: 131, kind: kPacketKindEvent, messageId: 2, jsonText: _protocolErrorEvent),
    expect: Reassembled(packetKind: 'event', messageId: 2, jsonText: _protocolErrorEvent),
  ),
  FragmentVector(
    id: 'frag-bad-magic',
    description: '第二片 magic_version=0xC0：丢弃组包缓冲，可上报 INVALID_MESSAGE',
    mtu: 23,
    frames: () {
      final f = _frames(mtu: 23, kind: kPacketKindRequest, messageId: 7, jsonText: _deviceInfoReq);
      f[1] = [0xC0, ...f[1].sublist(1)];
      return f;
    }(),
    expect: const Rejected('bad_magic'),
  ),
  FragmentVector(
    id: 'frag-unknown-packet-kind',
    description: '首片 packet_kind=0x7E：未知类型，丢弃组包缓冲',
    mtu: 23,
    frames: () {
      final f = _frames(mtu: 23, kind: kPacketKindRequest, messageId: 7, jsonText: _deviceInfoReq);
      f[0] = [kFragmentMagicVersion, 0x7E, ...f[0].sublist(2)];
      return f;
    }(),
    expect: const Rejected('unknown_packet_kind'),
  ),
  FragmentVector(
    id: 'frag-out-of-order',
    description: '片序颠倒（index 1 先于 0 到达）：终止组包',
    mtu: 23,
    frames: () {
      final f = _frames(mtu: 23, kind: kPacketKindRequest, messageId: 7, jsonText: _deviceInfoReq);
      return [f[1], f[0], f[2]];
    }(),
    expect: const Rejected('out_of_order'),
  ),
  FragmentVector(
    id: 'frag-missing-last',
    description: 'fragment_count=3 但末片永不到达：组包超时/不完整',
    mtu: 23,
    frames: () {
      final f = _frames(mtu: 23, kind: kPacketKindRequest, messageId: 7, jsonText: _deviceInfoReq);
      return f.sublist(0, 2);
    }(),
    expect: const Rejected('incomplete'),
  ),
  FragmentVector(
    id: 'frag-duplicate-index',
    description: 'index 0 重复到达：终止组包',
    mtu: 23,
    frames: () {
      final f = _frames(mtu: 23, kind: kPacketKindRequest, messageId: 7, jsonText: _deviceInfoReq);
      return [f[0], f[0], f[1], f[2]];
    }(),
    expect: const Rejected('duplicate_fragment'),
  ),
  FragmentVector(
    id: 'frag-header-changed',
    description: '同 message_id 中途 fragment_count 变化（3→2）：头部字段变化，终止组包',
    mtu: 23,
    frames: () {
      final f = _frames(mtu: 23, kind: kPacketKindRequest, messageId: 7, jsonText: _deviceInfoReq);
      f[1] = [kFragmentMagicVersion, kPacketKindRequest, 7, 1, 2, ...f[1].sublist(kFragmentHeaderSize)];
      return f;
    }(),
    expect: const Rejected('header_changed'),
  ),
];
