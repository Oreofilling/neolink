/// CT-Prov GATT 传输层：把信封请求/事件接到分片泵上。
/// 发送侧：信封编码 → 切片 → 逐帧写 C2D；接收侧：D2C 帧 → 重组 →
/// 信封解码 → 按响应 id 关联在途请求，事件走独立流（§5、§6）。
library;

import 'dart:async';

import 'package:ct_prov_core/ct_prov_core.dart';

import 'gatt_channel.dart';

/// 默认请求超时：设备端最慢路径为扫描 + 写入，10 秒足够宽。
const Duration kDefaultRequestTimeout = Duration(seconds: 10);

final class CtProvGattTransport {
  CtProvGattTransport(this._channel);

  final CtGattChannel _channel;
  StreamSubscription<List<int>>? _d2cSub;
  StreamSubscription<int>? _mtuSub;

  FragmentAssembler _assembler = FragmentAssembler(mtu: 23);
  final MessageIdAllocator _messageIds = MessageIdAllocator();
  final _pending = <int, Completer<ProvResponse>>{};
  final _events = StreamController<ProvEvent>.broadcast();
  final _frameErrors = StreamController<String>.broadcast();
  int _ignoredResponses = 0;

  /// 设备主动事件（v2.0 仅 protocol.error）。
  Stream<ProvEvent> get events => _events.stream;

  /// 分片拒绝理由（黄金向量 token）、envelope: 前缀的信封解码失败，
  /// 以及 mtu_changed（MTU 变化重建重组器时丢弃未完成缓冲）。
  Stream<String> get frameErrors => _frameErrors.stream;

  /// 无法关联到在途请求的响应计数（§6.4 要求忽略）。
  int get ignoredResponses => _ignoredResponses;

  /// 当前 MTU（来自通道）。
  int get mtu => _channel.mtu;

  /// 开始泵送。在 D2C 订阅建立后调用一次。
  void start() {
    if (_d2cSub != null) return;
    _d2cSub = _channel.d2cFrames.listen(_onFrame);
    _mtuSub = _channel.mtuChanges.listen((newMtu) {
      if (_assembler.hasPartialAssembly) {
        _frameErrors.add('mtu_changed');
      }
      _assembler = FragmentAssembler(mtu: newMtu);
    });
  }

  /// 停止泵送并释放流资源。
  Future<void> close() async {
    await _d2cSub?.cancel();
    await _mtuSub?.cancel();
    _d2cSub = null;
    _mtuSub = null;
    await _events.close();
    await _frameErrors.close();
    for (final completer in _pending.values) {
      completer.completeError(
        StateError('transport closed before response arrived'),
      );
    }
    _pending.clear();
  }

  /// 发送请求并等待同 id 响应。帧按序写出；响应经重组与信封解码后
  /// 按信封 id 关联。同 id 在途时重复发送直接抛 ArgumentError。
  Future<ProvResponse> sendRequest(
    ProvRequest request, {
    Duration timeout = kDefaultRequestTimeout,
  }) async {
    if (_pending.containsKey(request.id)) {
      throw ArgumentError('request id ${request.id} already in flight');
    }
    final completer = Completer<ProvResponse>();
    _pending[request.id] = completer;

    final frames = slicePacket(
      mtu: _channel.mtu,
      kind: ProvPacketKind.request,
      messageId: _messageIds.next(),
      jsonText: encodeRequest(id: request.id, op: request.opName, data: request.data),
    );
    for (final frame in frames) {
      await _channel.writeC2d(frame);
    }

    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      _pending.remove(request.id);
      rethrow;
    }
  }

  void _onFrame(List<int> frame) {
    switch (_assembler.feed(frame)) {
      case Assembled packet:
        _handlePacket(packet.packet);
      case FeedRejected rejection:
        _frameErrors.add(rejection.reason);
      case Assembling():
        break;
    }
  }

  void _handlePacket(ProvPacket packet) {
    final ProvEnvelope envelope;
    try {
      envelope = decodeEnvelope(packet.bytes);
    } on ProvEnvelopeException catch (e) {
      _frameErrors.add('envelope:${e.reason}');
      return;
    }
    switch (envelope) {
      case ProvResponse response:
        final completer = _pending.remove(response.id);
        if (completer == null || completer.isCompleted) {
          // §6.4：无法关联的响应必须忽略。
          _ignoredResponses++;
        } else {
          completer.complete(response);
        }
      case ProvEvent event:
        _events.add(event);
      case ProvRequest():
        // D2C 方向不该出现请求信封，计入忽略并在错误流留痕。
        _ignoredResponses++;
        _frameErrors.add('envelope:unexpected_request');
    }
  }
}
