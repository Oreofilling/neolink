/// GATT 分片层（§5）：单方向重组器。逐帧喂入 ATT 写入/指示负载，
/// 校验头部字段、片序与非末片尺寸，产出完整逻辑包或拒绝理由。
/// 协议规定每方向同时只允许一个在途组包，故每方向各持一个实例。
library;

import 'dart:convert' show utf8;

/// 分片头常量与上限（§5）。
const int kFragmentMagicVersion = 0xC1;
const int kPacketKindRequest = 0x01;
const int kPacketKindResponse = 0x02;
const int kPacketKindEvent = 0x03;
const int kPacketKindProtocolError = 0x7F;
const int kFragmentHeaderSize = 5;
const int kMaxLogicalPacketBytes = 4096;

/// 逻辑包类型（对应 §5 packet_kind 字节值）。
enum ProvPacketKind {
  request(kPacketKindRequest),
  response(kPacketKindResponse),
  event(kPacketKindEvent),
  protocolError(kPacketKindProtocolError);

  const ProvPacketKind(this.wireByte);
  final int wireByte;

  /// 按字节值反查；未知值返回 null（由重组器给出拒绝理由）。
  static ProvPacketKind? fromWireByte(int byte) {
    for (final kind in ProvPacketKind.values) {
      if (kind.wireByte == byte) return kind;
    }
    return null;
  }
}

/// 重组完成的一个完整逻辑包。bytes 为净负载（不含分片头）。
final class ProvPacket {
  const ProvPacket({
    required this.kind,
    required this.messageId,
    required this.bytes,
  });

  final ProvPacketKind kind;

  /// 分片层的 message_id（传输层序号，与信封层请求 id 是两个编号体系）。
  final int messageId;
  final List<int> bytes;

  /// 按 UTF-8 严格解码的 JSON 文本；非法 UTF-8 会抛 FormatException，
  /// 需要容错分类的场合请走信封层 decodeEnvelope(bytes)。
  String get jsonText => utf8.decode(bytes);
}

/// 喂入一帧后的组包状态。
sealed class FeedResult {
  const FeedResult();
}

/// 组包进行中（已收下该片，等待后续片）。
final class Assembling extends FeedResult {
  const Assembling();
}

/// 组包完成，产出一个完整逻辑包；组包缓冲随即复位。
final class Assembled extends FeedResult {
  const Assembled(this.packet);
  final ProvPacket packet;
}

/// 协议违规：丢弃当前组包缓冲。reason 为跨端稳定标识符，与黄金向量一致。
final class FeedRejected extends FeedResult {
  const FeedRejected(this.reason);
  final String reason;
}

/// 单方向分片重组器。用法：收到一帧就喂一帧，按 [FeedResult] 分支处理。
final class FragmentAssembler {
  FragmentAssembler({required this.mtu})
      : payloadMax = mtu - 3 - kFragmentHeaderSize {
    if (payloadMax < 1) {
      throw ArgumentError('mtu too small: $mtu (payload_max must be at least 1)');
    }
  }

  /// 约定 MTU；非末片负载必须恰好为 mtu - 3 - 5。
  final int mtu;
  final int payloadMax;

  int? _kindByte;
  int? _messageId;
  int? _count;
  int _expectedIndex = 0;
  final List<int> _buffer = [];

  /// 是否存在未完成的组包缓冲（缺片悬挂时为 true）。
  bool get hasPartialAssembly => _kindByte != null;

  /// 喂入一帧（含 5 字节分片头）。不保留调用方列表的引用。
  FeedResult feed(List<int> frame) {
    if (frame.length < kFragmentHeaderSize) {
      return _reject('malformed_frame');
    }
    final magic = frame[0];
    final kindByte = frame[1];
    final messageId = frame[2];
    final index = frame[3];
    final count = frame[4];

    if (magic != kFragmentMagicVersion) return _reject('bad_magic');
    if (ProvPacketKind.fromWireByte(kindByte) == null) {
      return _reject('unknown_packet_kind');
    }

    if (_kindByte == null) {
      if (count < 1) return _reject('malformed_frame');
      if (index != 0) return _reject('out_of_order');
      _kindByte = kindByte;
      _messageId = messageId;
      _count = count;
      _expectedIndex = 0;
    } else if (kindByte != _kindByte ||
        messageId != _messageId ||
        count != _count) {
      return _reject('header_changed');
    } else if (index < _expectedIndex) {
      return _reject('duplicate_fragment');
    } else if (index > _expectedIndex) {
      return _reject('out_of_order');
    }

    _buffer.addAll(frame.sublist(kFragmentHeaderSize));
    if (_buffer.length > kMaxLogicalPacketBytes) return _reject('oversized');

    final isFinal = index == _count! - 1;
    if (!isFinal) {
      // 非末片必须恰好装满 payload_max（§5），过短即无法继续组包。
      if (frame.length - kFragmentHeaderSize != payloadMax) {
        return _reject('malformed_frame');
      }
      _expectedIndex = index + 1;
      return const Assembling();
    }

    final packet = ProvPacket(
      kind: ProvPacketKind.fromWireByte(_kindByte!)!,
      messageId: _messageId!,
      bytes: List<int>.of(_buffer),
    );
    _reset();
    return Assembled(packet);
  }

  FeedRejected _reject(String reason) {
    _reset();
    return FeedRejected(reason);
  }

  void _reset() {
    _kindByte = null;
    _messageId = null;
    _count = null;
    _expectedIndex = 0;
    _buffer.clear();
  }
}
