import 'dart:async';

import 'package:provisioning_session/provisioning_session.dart';
import 'package:test/test.dart';

/// 记录钩子调用顺序的机器工厂。
(ProvisioningMachine, List<String>) makeMachine() {
  final calls = <String>[];
  final machine = ProvisioningMachine(
    onStopSources: () async => calls.add('stop_sources'),
    onReleaseLink: () async => calls.add('release_link'),
  );
  return (machine, calls);
}

/// 走完自检 → 扫描 → 出候选 → 连接 → 读能力 → 选节。
ProvisioningMachine connectedMachine() {
  final (machine, _) = makeMachine();
  machine.completeSelfCheck(canProceed: true);
  machine.reportCandidate();
  machine.selectCandidate();
  machine.transportReady();
  machine.capabilitiesRead();
  return machine;
}

void main() {
  test('初始相位为 selfChecking，phaseChanges 只发后续迁移', () async {
    final (machine, _) = makeMachine();
    expect(machine.phase, SessionPhase.selfChecking);

    final emitted = machine.phaseChanges.take(2).toList();
    machine.completeSelfCheck(canProceed: true);
    machine.reportCandidate();
    expect(await emitted, [
      SessionPhase.scanning,
      SessionPhase.resultsAvailable,
    ]);
  });

  group('合法链路', () {
    test('扫描 → 出候选', () {
      final (machine, _) = makeMachine();
      machine.completeSelfCheck(canProceed: true);
      machine.reportCandidate();
      expect(machine.phase, SessionPhase.resultsAvailable);
    });

    test('空扫描 → 重扫 → 出候选', () {
      final (machine, _) = makeMachine();
      machine.completeSelfCheck(canProceed: true);
      machine.reportScanTimeout();
      machine.rescan();
      machine.reportCandidate();
      expect(machine.phase, SessionPhase.resultsAvailable);
    });

    test('指引链路：扫描 → 指引扫描 → 展示指引 → 回扫描', () {
      final (machine, _) = makeMachine();
      machine.completeSelfCheck(canProceed: true);
      machine.beginGuideScan();
      machine.guideParsed();
      machine.rescan();
      expect(machine.phase, SessionPhase.scanning);
    });

    test('取消指引扫描回到扫描', () {
      final (machine, _) = makeMachine();
      machine.completeSelfCheck(canProceed: true);
      machine.beginGuideScan();
      machine.cancelGuideScan();
      expect(machine.phase, SessionPhase.scanning);
    });

    test('空结果也能进入指引扫描', () {
      final (machine, _) = makeMachine();
      machine.completeSelfCheck(canProceed: true);
      machine.reportScanTimeout();
      machine.beginGuideScan();
      expect(machine.phase, SessionPhase.guideScanning);
    });

    test('连接主链路到选节（M2 止点）', () {
      final machine = connectedMachine();
      expect(machine.phase, SessionPhase.choosingSections);
    });

    test('下发全链路：编辑 → 下发 → 完成 → 清理 → 扫描', () async {
      final machine = connectedMachine();
      machine.beginEditing();
      machine.beginDelivery();
      machine.deliveryStored();
      expect(machine.phase, SessionPhase.completed);
      await machine.cleanup();
      expect(machine.phase, SessionPhase.scanning);
    });

    test('下发失败 → 回编辑重试', () {
      final machine = connectedMachine();
      machine.beginEditing();
      machine.beginDelivery();
      machine.failOperation('storage_failed', 'STORAGE_FAILED');
      machine.editAgain();
      expect(machine.phase, SessionPhase.editingConfig);
    });

    test('断链与恢复：编辑中断链 → linkLost → 原位恢复', () {
      final machine = connectedMachine();
      machine.beginEditing();
      machine.markLinkLost();
      expect(machine.phase, SessionPhase.linkLost);
      machine.linkRestored(editing: true);
      expect(machine.phase, SessionPhase.editingConfig);
      machine.markLinkLost();
      machine.linkRestored(editing: false);
      expect(machine.phase, SessionPhase.choosingSections);
    });

    test('断链可从四个会话相位进入，清理是逃生门', () async {
      // choosingSections (connectedMachine already stops there).
      final choosing = connectedMachine();
      choosing.markLinkLost();
      expect(choosing.phase, SessionPhase.linkLost);
      // Walk editingConfig -> delivering -> operationError in turn.
      final machine = connectedMachine();
      machine.beginEditing();
      machine.markLinkLost();
      machine.linkRestored(editing: true);
      machine.beginDelivery();
      machine.markLinkLost();
      expect(machine.phase, SessionPhase.linkLost);
      machine.linkRestored(editing: true);
      machine.beginDelivery();
      machine.failOperation('storage_failed');
      machine.markLinkLost();
      expect(machine.phase, SessionPhase.linkLost);
      await machine.cleanup();
      expect(machine.phase, SessionPhase.scanning);
    });

    test('completed 不接受断链迁移（应用配置后设备重启属正常断开，不弹窗）', () {
      final machine = connectedMachine();
      machine.beginEditing();
      machine.beginDelivery();
      machine.deliveryStored();
      expect(() => machine.markLinkLost(), throwsStateError);
    });
  });

  group('web 模式（M5：softAP join 后直接持有链路开网页）', () {
    test('connecting → webBrowsing → 清理退出（释放链路）', () async {
      final (machine, calls) = makeMachine();
      machine.completeSelfCheck(canProceed: true);
      machine.reportCandidate();
      await machine.selectCandidate();
      machine.webLinkReady();
      expect(machine.phase, SessionPhase.webBrowsing);

      await machine.cleanup();
      expect(machine.phase, SessionPhase.scanning);
      // The held link must go through the release hook on exit (restores
      // the pre-join Wi-Fi), same funnel as every other chain.
      expect(calls, contains('release_link'));
    });

    test('webBrowsing 不接受能力链迁移（无能力读取）', () {
      final (machine, _) = makeMachine();
      machine.completeSelfCheck(canProceed: true);
      machine.reportCandidate();
      machine.selectCandidate();
      machine.webLinkReady();
      expect(
        () => machine.transportReady(),
        throwsStateError,
      );
      expect(
        () => machine.capabilitiesRead(),
        throwsStateError,
      );
    });

    test('非 connecting 相位不得进入 webBrowsing', () {
      final (machine, _) = makeMachine();
      machine.completeSelfCheck(canProceed: true);
      machine.reportCandidate();
      expect(() => machine.webLinkReady(), throwsStateError);
    });
  });

  group('资源释放钩子', () {
    test('选定候选时停止发现源（不停链路）', () async {
      final (machine, calls) = makeMachine();
      machine.completeSelfCheck(canProceed: true);
      machine.reportCandidate();
      await machine.selectCandidate();
      expect(calls, ['stop_sources']);
    });

    test('连接失败：先释放链路，可再返回候选列表', () async {
      final (machine, calls) = makeMachine();
      machine.completeSelfCheck(canProceed: true);
      machine.reportCandidate();
      await machine.selectCandidate();
      await machine.failConnection('connect_timeout');
      expect(calls, ['stop_sources', 'release_link']);
      expect(machine.phase, SessionPhase.connectionError);
      machine.switchCandidate();
      expect(machine.phase, SessionPhase.resultsAvailable);
    });

    test('能力失败：释放链路后换设备', () async {
      final (machine, calls) = makeMachine();
      machine.completeSelfCheck(canProceed: true);
      machine.reportCandidate();
      await machine.selectCandidate();
      machine.transportReady();
      await machine.failCapabilities('capabilities_error', 'BUSY');
      expect(calls, ['stop_sources', 'release_link']);
      machine.switchCandidate();
      expect(machine.phase, SessionPhase.resultsAvailable);
    });

    test('清理：链路先于停源释放，之后回到扫描', () async {
      final (machine, calls) = makeMachine();
      machine.completeSelfCheck(canProceed: true);
      machine.reportCandidate();
      await machine.selectCandidate();
      machine.transportReady();
      await machine.cleanup();
      expect(calls, ['stop_sources', 'release_link', 'stop_sources']);
      expect(machine.phase, SessionPhase.scanning);
    });

    test('自检阶段也可直接清理退出', () async {
      final (machine, calls) = makeMachine();
      await machine.cleanup();
      expect(calls, ['release_link', 'stop_sources']);
      expect(machine.phase, SessionPhase.scanning);
    });

    test('并发清理只执行一次释放', () async {
      final (machine, calls) = makeMachine();
      machine.completeSelfCheck(canProceed: true);
      final first = machine.cleanup();
      final second = machine.cleanup();
      await Future.wait([first, second]);
      expect(calls, ['release_link', 'stop_sources']);
      expect(machine.phase, SessionPhase.scanning);
    });
  });

  group('问题流', () {
    test('自检不通过：停留并发布 environment_blocked', () async {
      final (machine, _) = makeMachine();
      final emitted = machine.problems.take(1).toList();
      machine.completeSelfCheck(canProceed: false, detail: 'no radio');
      final problem = (await emitted).single;
      expect(problem.phase, SessionPhase.selfChecking);
      expect(problem.reason, 'environment_blocked');
      expect(problem.message, 'no radio');
      expect(machine.phase, SessionPhase.selfChecking);
      // 修复后重检放行（图中的 SelfChecking 自环）。
      machine.completeSelfCheck(canProceed: true);
      expect(machine.phase, SessionPhase.scanning);
    });

    test('连接失败发布问题，携带相位与原因', () async {
      final (machine, _) = makeMachine();
      machine.completeSelfCheck(canProceed: true);
      machine.reportCandidate();
      await machine.selectCandidate();
      final emitted = machine.problems.take(1).toList();
      await machine.failConnection('pairing_failed', 'timeout');
      final problem = (await emitted).single;
      expect(problem.phase, SessionPhase.connectionError);
      expect(problem.reason, 'pairing_failed');
    });

    test('reportProblem 不改变相位', () async {
      final (machine, _) = makeMachine();
      machine.completeSelfCheck(canProceed: true);
      final emitted = machine.problems.take(1).toList();
      machine.reportProblem('frame_error', 'crc mismatch');
      final problem = (await emitted).single;
      expect(problem.phase, SessionPhase.scanning);
      expect(machine.phase, SessionPhase.scanning);
    });
  });

  group('非法迁移抛 StateError', () {
    test('未自检完成就报告候选', () {
      final (machine, _) = makeMachine();
      expect(machine.reportCandidate, throwsStateError);
    });

    test('扫描相位直接读能力完成', () {
      final (machine, _) = makeMachine();
      machine.completeSelfCheck(canProceed: true);
      expect(machine.capabilitiesRead, throwsStateError);
    });

    test('空结果相位选定候选（须先重扫出候选）', () {
      final (machine, _) = makeMachine();
      machine.completeSelfCheck(canProceed: true);
      machine.reportScanTimeout();
      expect(machine.selectCandidate, throwsStateError);
    });

    test('连接相位直接进入选节', () {
      final (machine, _) = makeMachine();
      machine.completeSelfCheck(canProceed: true);
      machine.reportCandidate();
      machine.selectCandidate();
      expect(machine.capabilitiesRead, throwsStateError);
    });

    test('readingCapabilities 相位重复宣告 transportReady', () {
      final (machine, _) = makeMachine();
      machine.completeSelfCheck(canProceed: true);
      machine.reportCandidate();
      machine.selectCandidate();
      machine.transportReady();
      expect(machine.transportReady, throwsStateError);
    });

    test('完成相位只能清理（不能直接回扫描）', () {
      final machine = connectedMachine();
      machine.beginEditing();
      machine.beginDelivery();
      machine.deliveryStored();
      expect(machine.rescan, throwsStateError);
    });
  });

  test('dispose 关闭流', () async {
    final (machine, _) = makeMachine();
    await machine.dispose();
    expect(machine.isClosed, isTrue);
  });
}
