/// 配置会话统一状态机（技术设计 §11）。
///
/// 纯迁移表实现：适配器回调只经本机发布事件与页面跳转，资源释放
/// （停止发现源、断开链路）由构造注入的钩子在进入相应相位时执行。
/// 非法迁移是编程错误，抛 [StateError] 快速暴露；调用方（控制器）需
/// 自行串行化调用，并对迟到事件按当前相位先行过滤。
///
/// 对 §11 图的两处补充：ScanEmpty→Scanning（空结果后重扫）与
/// GuideScanning→Scanning（取消指引扫描）；任意相位→Cleaning 作为
/// 重来/退出的逃生门（图中仅 Completed→Cleaning）。
library;

import 'dart:async';

/// 会话相位全集（§11）。`stored` 在图中只是 Delivering→Completed 的
/// 迁移标签而非独立状态，故不设该值。
enum SessionPhase {
  selfChecking,
  scanning,
  resultsAvailable,
  scanEmpty,
  guideScanning,
  showingGuide,
  connecting,
  webBrowsing,
  readingCapabilities,
  choosingSections,
  editingConfig,
  delivering,
  operationError,
  linkLost,
  connectionError,
  capabilityError,
  completed,
  cleaning,
}

/// §11 合法迁移表：源相位 → 可达相位集合。
const Map<SessionPhase, Set<SessionPhase>> kLegalTransitions = {
  SessionPhase.selfChecking: {
    SessionPhase.scanning,
    SessionPhase.cleaning,
  },
  SessionPhase.scanning: {
    SessionPhase.resultsAvailable,
    SessionPhase.scanEmpty,
    SessionPhase.guideScanning,
    SessionPhase.cleaning,
  },
  SessionPhase.scanEmpty: {
    SessionPhase.guideScanning,
    SessionPhase.scanning,
    SessionPhase.cleaning,
  },
  SessionPhase.guideScanning: {
    SessionPhase.showingGuide,
    SessionPhase.scanning,
    SessionPhase.cleaning,
  },
  SessionPhase.showingGuide: {
    SessionPhase.scanning,
    SessionPhase.cleaning,
  },
  SessionPhase.resultsAvailable: {
    SessionPhase.connecting,
    SessionPhase.cleaning,
  },
  SessionPhase.connecting: {
    SessionPhase.webBrowsing,
    SessionPhase.readingCapabilities,
    SessionPhase.connectionError,
    SessionPhase.cleaning,
  },
  SessionPhase.webBrowsing: {SessionPhase.cleaning},
  SessionPhase.readingCapabilities: {
    SessionPhase.choosingSections,
    SessionPhase.capabilityError,
    SessionPhase.cleaning,
  },
  SessionPhase.choosingSections: {
    SessionPhase.editingConfig,
    SessionPhase.linkLost,
    SessionPhase.cleaning,
  },
  SessionPhase.editingConfig: {
    SessionPhase.delivering,
    SessionPhase.linkLost,
    SessionPhase.cleaning,
  },
  SessionPhase.delivering: {
    SessionPhase.completed,
    SessionPhase.operationError,
    SessionPhase.linkLost,
    SessionPhase.cleaning,
  },
  SessionPhase.operationError: {
    SessionPhase.editingConfig,
    SessionPhase.linkLost,
    SessionPhase.cleaning,
  },
  SessionPhase.linkLost: {
    SessionPhase.choosingSections,
    SessionPhase.editingConfig,
    SessionPhase.cleaning,
  },
  SessionPhase.connectionError: {
    SessionPhase.resultsAvailable,
    SessionPhase.cleaning,
  },
  SessionPhase.capabilityError: {
    SessionPhase.resultsAvailable,
    SessionPhase.cleaning,
  },
  SessionPhase.completed: {SessionPhase.cleaning},
  SessionPhase.cleaning: {SessionPhase.scanning},
};

/// 错误/问题呈现流的负载：phase 为发生相位，reason 为稳定标识
/// （UI 映射文案），message 携带详情（设备侧错误码等）。
final class SessionProblem {
  const SessionProblem(this.phase, this.reason, [this.message]);

  final SessionPhase phase;
  final String reason;
  final String? message;

  @override
  String toString() => message == null
      ? 'SessionProblem(${phase.name}/$reason)'
      : 'SessionProblem(${phase.name}/$reason: $message)';
}

/// 统一状态机。创建即处于 selfChecking；会话结束后经 [cleanup] 回到
/// scanning 循环或 [dispose] 收尾。
final class ProvisioningMachine {
  ProvisioningMachine({
    Future<void> Function()? onStopSources,
    Future<void> Function()? onReleaseLink,
  })  : _stopSources = onStopSources,
        _releaseLink = onReleaseLink;

  final Future<void> Function()? _stopSources;
  final Future<void> Function()? _releaseLink;

  SessionPhase _phase = SessionPhase.selfChecking;
  final StreamController<SessionPhase> _phaseChanges =
      StreamController<SessionPhase>.broadcast();
  final StreamController<SessionProblem> _problems =
      StreamController<SessionProblem>.broadcast();

  /// 当前相位。
  SessionPhase get phase => _phase;

  /// 相位迁移流（仅变更时发事件；初值用 [phase] 读取）。
  Stream<SessionPhase> get phaseChanges => _phaseChanges.stream;

  /// 问题流：自检失败、连接/能力/下发失败与通用协议错误统一从这里出。
  Stream<SessionProblem> get problems => _problems.stream;

  /// 流是否已随 [dispose] 关闭。
  bool get isClosed => _phaseChanges.isClosed && _problems.isClosed;

  void _transition(SessionPhase to) {
    final legal = kLegalTransitions[_phase]!;
    if (!legal.contains(to)) {
      throw StateError('illegal transition ${_phase.name} -> ${to.name}');
    }
    _phase = to;
    _phaseChanges.add(to);
  }

  void _publish(String reason, [String? message]) {
    _problems.add(SessionProblem(_phase, reason, message));
  }

  /// 自检结束：至少一条通道可用或仅通道受限即放行进入扫描；全部通道
  /// 不可用时停留并发布问题（修复后可再次调用，即图中的自环）。
  void completeSelfCheck({required bool canProceed, String? detail}) {
    if (canProceed) {
      _transition(SessionPhase.scanning);
    } else {
      _publish('environment_blocked', detail);
    }
  }

  /// 扫描中出现候选。
  void reportCandidate() => _transition(SessionPhase.resultsAvailable);

  /// 扫描超时且无候选。
  void reportScanTimeout() => _transition(SessionPhase.scanEmpty);

  /// 空结果或指引流程后重新扫描。
  void rescan() => _transition(SessionPhase.scanning);

  /// 进入指引二维码扫描。
  void beginGuideScan() => _transition(SessionPhase.guideScanning);

  /// 指引二维码解析成功。
  void guideParsed() => _transition(SessionPhase.showingGuide);

  /// 取消指引扫描回到普通扫描（对 §11 图的补充）。
  void cancelGuideScan() => _transition(SessionPhase.scanning);

  /// 选定候选进入连接：先迁移再停止发现源（注册表候选保留，供失败后
  /// 返回列表重选）。
  Future<void> selectCandidate() async {
    _transition(SessionPhase.connecting);
    await _stopSources?.call();
  }

  /// 链路建立完成（连接、配对加密、D2C 订阅、传输泵就绪）。
  void transportReady() => _transition(SessionPhase.readingCapabilities);

  /// softAP join succeeded in web-console mode (M5): the link is held for
  /// the device web page opened in the browser; the only way out is
  /// [cleanup], which releases the link (restoring the previous Wi-Fi)
  /// and returns to the scan loop. No capability read runs in this mode.
  void webLinkReady() => _transition(SessionPhase.webBrowsing);

  /// 能力读取完成。
  void capabilitiesRead() => _transition(SessionPhase.choosingSections);

  /// 连接失败：迁移到 connectionError 并释放链路。
  Future<void> failConnection(String reason, [String? message]) async {
    _transition(SessionPhase.connectionError);
    _publish(reason, message);
    await _releaseLink?.call();
  }

  /// 能力读取失败：迁移到 capabilityError 并释放链路。
  Future<void> failCapabilities(String reason, [String? message]) async {
    _transition(SessionPhase.capabilityError);
    _publish(reason, message);
    await _releaseLink?.call();
  }

  /// 连接/能力失败后返回候选列表重选（链路已在失败时释放）。
  void switchCandidate() => _transition(SessionPhase.resultsAvailable);

  /// 选定配置节进入表单编辑（M3）。
  void beginEditing() => _transition(SessionPhase.editingConfig);

  /// 表单提交进入下发（M3）。
  void beginDelivery() => _transition(SessionPhase.delivering);

  /// config.set 持久化成功。
  void deliveryStored() => _transition(SessionPhase.completed);

  /// 下发被拒（校验或存储失败）：停留 operationError，可经 [editAgain]
  /// 回到编辑。
  void failOperation(String reason, [String? message]) {
    _transition(SessionPhase.operationError);
    _publish(reason, message);
  }

  /// 下发失败后修改再试。
  void editAgain() => _transition(SessionPhase.editingConfig);

  /// Link dropped mid session (BLE supervision timeout / device sleep):
  /// everything being edited is kept; a successful reconnect re-enters in
  /// place via [linkRestored]. The controller releases the link before
  /// calling (the disconnect event itself is the release signal).
  void markLinkLost() => _transition(SessionPhase.linkLost);

  /// Reconnect succeeded: back to editing when a module is open, otherwise
  /// back to module selection.
  void linkRestored({required bool editing}) => _transition(
        editing ? SessionPhase.editingConfig : SessionPhase.choosingSections,
      );

  /// 任意相位进入清理：释放链路 + 停止发现源，完成后回到扫描循环。
  /// 钩子必须可重入（链路可能已断、源可能已停）。
  Future<void> cleanup() async {
    if (_phase == SessionPhase.cleaning) return;
    _transition(SessionPhase.cleaning);
    await _releaseLink?.call();
    await _stopSources?.call();
    _transition(SessionPhase.scanning);
  }

  /// 发布不改变相位的问题（如传输层帧错误、迟到事件告警）。
  void reportProblem(String reason, [String? message]) =>
      _publish(reason, message);

  /// 收尾：关闭流。不执行迁移与钩子（先 [cleanup] 再 dispose）。
  Future<void> dispose() async {
    await _phaseChanges.close();
    await _problems.close();
  }
}
