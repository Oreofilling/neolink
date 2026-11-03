/// 配置流程控制器（M2-4）：把统一状态机、发现注册表、发现源、环境
/// 探测与会话客户端组装成 UI 可订阅的 [ChangeNotifier]。
///
/// 页面不直接驱动状态机，也不直接触碰适配器；控制器是唯一编排点：
/// 迁移合法性由机器保证，控制器负责把异步链路结果翻译成机器事件，
/// 并对迟到事件按当前相位过滤（机器对非法迁移直接抛错）。
library;

import 'dart:async';

import 'package:ble_universal/ble_universal.dart';
import 'package:communication_domain/communication_domain.dart';
import 'package:flutter/foundation.dart';
// 能力侧的 ConfigSection 与 communication_domain 节类型重名：控制器
// 语境里 ConfigSection 一律指节草稿，能力节只经 capabilities.sections 迭代。
import 'package:provisioning_session/provisioning_session.dart' hide ConfigSection;

import '../services/environment_probe.dart';
import 'section_editing.dart';

/// 把桌面端环境探测与三路通道状态映射进会话状态机。
class ProvisioningController extends ChangeNotifier {
  ProvisioningController({
    DesktopEnvironmentProbe? environmentProbe,
    DiscoverySource? discoverySource,
    Future<void> Function(String deviceId)? establishPairing,
    Future<CtGattChannel> Function(
      String deviceId,
      void Function(String step) onStep,
    )?
    connectChannel,
    this.scanTimeout = const Duration(seconds: 20),
    this.ttl = const Duration(seconds: 12),
  }) : _probe = environmentProbe ?? DesktopEnvironmentProbe(),
       _source = discoverySource ?? BleDiscoverySource(),
       _pair =
           establishPairing ?? ((deviceId) => establishSystemBond(deviceId)),
       _connect =
           connectChannel ??
           ((deviceId, onStep) =>
               UniversalCtGattChannel.open(deviceId, onStep: onStep)) {
    _machine = ProvisioningMachine(
      onStopSources: _stopSources,
      onReleaseLink: _releaseLink,
    );
    _phaseSub = _machine.phaseChanges.listen(_onPhaseChanged);
    _problemSub = _machine.problems.listen((problem) {
      lastProblem = problem;
      notifyListeners();
    });
  }

  /// 扫描窗口：超过仍无候选 → scanEmpty。
  final Duration scanTimeout;

  /// 候选淘汰窗口（与扫描任务同生命周期，不落盘）。
  final Duration ttl;

  final DesktopEnvironmentProbe _probe;
  final DiscoverySource _source;
  final Future<void> Function(String deviceId) _pair;
  final Future<CtGattChannel> Function(
    String deviceId,
    void Function(String step) onStep,
  )
  _connect;

  late final ProvisioningMachine _machine;
  late final StreamSubscription<SessionPhase> _phaseSub;
  late final StreamSubscription<SessionProblem> _problemSub;

  DiscoveryRegistry _registry = DiscoveryRegistry();
  StreamSubscription<DiscoveryCandidate>? _candidateSub;
  Timer? _scanTimer;
  Timer? _sweepTimer;

  CtGattChannel? _channel;
  CtSessionClient? _session;

  /// 自检结果（首次完成后保持，供各页展示通道状态）。
  EnvironmentCheckReport? environmentReport;

  /// 自检是否正在执行（页面骨架态）。
  bool get selfChecking => _selfChecking;
  bool _selfChecking = false;

  /// 最近一次问题（连接/能力/下发失败与协议错误）。
  SessionProblem? lastProblem;

  /// 连接序列的分步进度（骨架屏进度行，最新在末尾）。
  final List<String> connectSteps = <String>[];

  DiscoveryCandidate? selectedCandidate;
  DeviceInfoResult? deviceInfo;
  CapabilitiesResult? capabilities;

  SessionPhase get phase => _machine.phase;
  List<DiscoveryCandidate> get candidates => _registry.snapshot;

  /// 状态机相位 → 侧栏页面 id（自动跟随；用户也可点击已解锁页）。
  String get pageForPhase => switch (_machine.phase) {
    SessionPhase.selfChecking => 'selfcheck',
    SessionPhase.scanning ||
    SessionPhase.resultsAvailable ||
    SessionPhase.guideScanning ||
    SessionPhase.showingGuide => 'scan',
    SessionPhase.scanEmpty => 'empty',
    SessionPhase.connecting ||
    SessionPhase.readingCapabilities ||
    SessionPhase.connectionError ||
    SessionPhase.capabilityError => 'connect',
    SessionPhase.choosingSections => 'caps',
    SessionPhase.editingConfig ||
    SessionPhase.delivering ||
    SessionPhase.operationError => 'deliver',
    SessionPhase.completed => 'result',
    SessionPhase.cleaning => 'scan',
  };

  /// 侧栏解锁：流程页随相位推进；表单/结果页随本次编辑会话开放，
  /// 收尾清理后回到扫描即重新上锁。
  bool isNavUnlocked(String pageId) => switch (pageId) {
    'selfcheck' => true,
    'scan' || 'empty' => _machine.phase != SessionPhase.selfChecking,
    'guide' => false,
    'connect' => switch (_machine.phase) {
      SessionPhase.connecting ||
      SessionPhase.readingCapabilities ||
      SessionPhase.connectionError ||
      SessionPhase.capabilityError => true,
      _ => false,
    },
    'caps' => capabilities != null,
    'deliver' => switch (_machine.phase) {
      SessionPhase.editingConfig ||
      SessionPhase.delivering ||
      SessionPhase.operationError ||
      SessionPhase.completed => true,
      _ => false,
    },
    'result' => _machine.phase == SessionPhase.completed,
    _ => false,
  };

  /// 环境自检：探测三路通道 → 机器放行或阻塞（阻塞时停留自检页）。
  Future<void> runSelfCheck() async {
    if (_machine.phase != SessionPhase.selfChecking || _selfChecking) return;
    _selfChecking = true;
    notifyListeners();
    environmentReport = await _probe.probe();
    _selfChecking = false;
    _machine.completeSelfCheck(
      canProceed: environmentReport!.canProceed,
      detail: environmentReport!.channels
          .where((entry) => entry.capability != ChannelCapability.available)
          .map((entry) => '${entry.channel.name}: ${entry.reason}')
          .join(', '),
    );
    notifyListeners();
  }

  /// 从候选列表选定设备：进入连接链（配对 → 通道 → 会话 → 读能力）。
  Future<void> selectCandidate(DiscoveryCandidate candidate) async {
    if (_machine.phase != SessionPhase.resultsAvailable) return;
    selectedCandidate = candidate;
    deviceInfo = null;
    capabilities = null;
    connectSteps.clear();
    notifyListeners();
    await _machine.selectCandidate();
    await _connectChain(candidate);
  }

  Future<void> _connectChain(DiscoveryCandidate candidate) async {
    final deviceId = candidate.candidateId;
    void onStep(String step) {
      connectSteps.add(step);
      notifyListeners();
    }

    // 第一段：系统配对 + GATT 通道 → 失败按连接错误处理。
    CtGattChannel channel;
    try {
      onStep('pairing');
      await _pair(deviceId);
      if (_machine.phase != SessionPhase.connecting) return;
      onStep('opening gatt');
      channel = await _connect(deviceId, onStep);
      _channel = channel;
    } catch (error) {
      if (_machine.phase == SessionPhase.connecting) {
        await _machine.failConnection('connect_failed', '$error');
      }
      return;
    }
    if (_machine.phase != SessionPhase.connecting) return;
    _machine.transportReady();

    // 第二段：会话 → device.info → capabilities → 失败按能力错误处理。
    final session = CtSessionClient(channel);
    _session = session;
    try {
      await session.open();
      if (_machine.phase != SessionPhase.readingCapabilities) return;
      onStep('reading device info');
      deviceInfo = await session.fetchDeviceInfo();
      onStep('reading capabilities');
      capabilities = await session.fetchCapabilities();
      _machine.capabilitiesRead();
    } on ProvSessionException catch (error) {
      if (_machine.phase == SessionPhase.readingCapabilities) {
        await _machine.failCapabilities(error.reason, error.message);
      }
    } catch (error) {
      if (_machine.phase == SessionPhase.readingCapabilities) {
        await _machine.failCapabilities('capabilities_failed', '$error');
      }
    } finally {
      notifyListeners();
    }
  }

  /// 连接/能力失败后返回候选列表（候选保留，可直接重选）。
  void switchCandidate() {
    if (_machine.phase != SessionPhase.connectionError &&
        _machine.phase != SessionPhase.capabilityError) {
      return;
    }
    _machine.switchCandidate();
    notifyListeners();
  }

  /// 空结果/结果页重扫：清理链路与源，回扫描循环重新开始。
  Future<void> rescan() async {
    await _machine.cleanup();
    notifyListeners();
  }

  // ---- M3: form drafts, delivery, network scan ----

  /// Section names in this editing round (capability order, configurable only).
  List<String> editingSections = const [];

  /// Section name -> form draft (immutable section objects; field-level
  /// updates flow through section_editing helpers).
  Map<String, ConfigSection> drafts = const {};

  /// Section name -> current validation problems (per-field marks; empty
  /// means the section passes).
  Map<String, List<FieldProblem>> sectionProblems = const {};

  /// Last config.set result (rendered on the completed page).
  SetConfigResult? deliveryResult;

  /// Whether config.get prefill finished (unsupported/failed both count as
  /// done; the form stays usable either way).
  bool prefillDone = false;

  /// Network scan state: target section / fetched items / cursor (the §9
  /// cursor is only valid within the current connection).
  String? scanSection;
  List<ScanNetwork> scanItems = const [];
  bool scanMore = false;
  String _scanCursor = '';

  /// communication.scan in flight (scan button state).
  bool get networkScanning => _networkScanning;
  bool _networkScanning = false;

  /// Network section names declared by capabilities (comm.type options).
  Set<String> get declaredNetworks => {
    for (final section in capabilities?.sections ?? const [])
      if (section.kind == ConfigSectionKind.network) section.name,
  };

  /// Editing sections as name -> declared fields (single source for both
  /// payload assembly and validation).
  Map<String, List<String>> get _editingSectionFields => {
    for (final name in editingSections)
      name:
          capabilities!.sections
              .firstWhere((section) => section.name == name)
              .fields,
  };

  /// Selection done, enter the form (M3 entry): seed empty drafts ->
  /// prefill from read-back -> editing phase.
  Future<void> beginEditing(Set<String> sectionNames) async {
    if (_machine.phase != SessionPhase.choosingSections) return;
    final caps = capabilities;
    if (caps == null) return;
    final ordered = [
      for (final section in caps.sections)
        if (section.configurable && sectionNames.contains(section.name))
          section.name,
    ];
    if (ordered.isEmpty) return;
    editingSections = ordered;
    drafts = {
      for (final name in ordered)
        name: defaultSectionFor(name, declaredNetworks: declaredNetworks),
    };
    sectionProblems = const {};
    deliveryResult = null;
    prefillDone = false;
    scanSection = null;
    scanItems = const [];
    scanMore = false;
    _scanCursor = '';
    _machine.beginEditing();
    notifyListeners();
    // config.get prefill degrades gracefully (unsupported/failed never
    // blocks the form).
    unawaited(_prefillDrafts());
  }

  /// Fills drafts from config.get read-back (declared fields only; masked
  /// secrets are skipped).
  Future<void> _prefillDrafts() async {
    final session = _session;
    if (session == null) {
      prefillDone = true;
      return;
    }
    Map<String, Map<String, Object?>>? stored;
    try {
      stored = await session.getConfig();
    } catch (error) {
      _machine.reportProblem('config_get_failed', '$error');
    }
    prefillDone = true;
    if (stored == null) {
      notifyListeners();
      return;
    }
    if (_machine.phase != SessionPhase.editingConfig) return;
    drafts = {
      for (final entry in drafts.entries)
        entry.key: prefillSection(
          entry.value,
          stored[entry.key] ?? const {},
          declaredFields: _editingSectionFields[entry.key] ?? const [],
        ),
    };
    _validateDrafts();
    notifyListeners();
  }

  /// Field update from the form: store the draft and re-validate that
  /// section immediately.
  void updateDraft(ConfigSection section) {
    if (_machine.phase != SessionPhase.editingConfig) return;
    if (!editingSections.contains(section.name)) return;
    drafts = {...drafts, section.name: section};
    _validateSection(section.name);
    notifyListeners();
  }

  void _validateSection(String name) {
    final problems = validateSection(
      drafts[name]!,
      declaredFields: _editingSectionFields[name] ?? const [],
      declaredNetworks: declaredNetworks,
    );
    sectionProblems = {...sectionProblems, name: problems};
  }

  void _validateDrafts() {
    for (final name in editingSections) {
      _validateSection(name);
    }
  }

  /// Assembles the payload (shared by form preview and submit; problems are
  /// grouped into sectionProblems).
  ConfigPayload assembleDraftPayload() => assembleConfigPayload(
    drafts,
    sectionFields: _editingSectionFields,
  );

  /// Submit: local validation failure stays on the form with per-field
  /// marks; success means config.set persisted (idempotent overwrite, §10),
  /// failure keeps the drafts and moves to operationError.
  Future<void> submit() async {
    if (_machine.phase != SessionPhase.editingConfig) return;
    final session = _session;
    if (session == null) return;

    // Field-level validation runs per section (validateSection reports bare
    // field names); section-level gating comes from assembly.
    _validateDrafts();
    if (sectionProblems.values.any((list) => list.isNotEmpty)) {
      notifyListeners();
      return;
    }
    final payload = assembleDraftPayload();
    if (payload.problems.isNotEmpty) {
      sectionProblems = {
        for (final problem in payload.problems)
          problem.field: [problem],
      };
      notifyListeners();
      return;
    }

    _machine.beginDelivery();
    notifyListeners();
    try {
      deliveryResult = await session.setConfig(payload.payload);
      _machine.deliveryStored();
    } on ProvSessionException catch (error) {
      deliveryResult = null;
      _machine.failOperation(error.reason, error.message);
    } catch (error) {
      deliveryResult = null;
      _machine.failOperation('config_set_failed', '$error');
    }
    notifyListeners();
  }

  /// Back to the form after a rejected delivery (drafts preserved).
  void editAgain() {
    if (_machine.phase != SessionPhase.operationError) return;
    _machine.editAgain();
    notifyListeners();
  }

  /// Finishes the session: §11 close -> release the link -> back to the
  /// scan loop.
  Future<void> finishSession() async {
    if (_machine.phase != SessionPhase.completed) return;
    final session = _session;
    if (session != null) {
      try {
        await session.closeSession();
      } catch (_) {
        // A rejected close does not block: the link is released by the
        // cleanup path regardless.
      }
    }
    await _machine.cleanup();
    _clearEditingState();
    notifyListeners();
  }

  void _clearEditingState() {
    editingSections = const [];
    drafts = const {};
    sectionProblems = const {};
    deliveryResult = null;
    prefillDone = false;
    scanSection = null;
    scanItems = const [];
    scanMore = false;
    _scanCursor = '';
  }

  /// Scans networks (§9): only capability-scannable sections; results feed
  /// the form's SSID picker.
  Future<void> scanNetworks(String section) async {
    if (_machine.phase != SessionPhase.editingConfig || _networkScanning) {
      return;
    }
    final session = _session;
    if (session == null) return;
    _networkScanning = true;
    scanSection = section;
    scanItems = const [];
    scanMore = false;
    _scanCursor = '';
    notifyListeners();
    try {
      final result = await session.scanNetworks(section: section);
      scanItems = result.items;
      scanMore = result.more;
      _scanCursor = result.cursor;
    } on ProvSessionException catch (error) {
      _machine.reportProblem(error.reason, error.message);
      scanItems = const [];
      scanMore = false;
    } catch (error) {
      _machine.reportProblem('scan_failed', '$error');
      scanItems = const [];
      scanMore = false;
    } finally {
      _networkScanning = false;
      notifyListeners();
    }
  }

  /// Cursor-based next page (§9: cursor only valid in this connection).
  Future<void> loadMoreNetworks() async {
    if (!scanMore ||
        _scanCursor.isEmpty ||
        _networkScanning ||
        _machine.phase != SessionPhase.editingConfig) {
      return;
    }
    final session = _session;
    if (session == null) return;
    _networkScanning = true;
    notifyListeners();
    try {
      final result = await session.scanNetworks(
        section: scanSection!,
        cursor: _scanCursor,
      );
      scanItems = [...scanItems, ...result.items];
      scanMore = result.more;
      _scanCursor = result.cursor;
    } on ProvSessionException catch (error) {
      _machine.reportProblem(error.reason, error.message);
      scanMore = false;
    } catch (error) {
      _machine.reportProblem('scan_failed', '$error');
      scanMore = false;
    } finally {
      _networkScanning = false;
      notifyListeners();
    }
  }

  /// Picks a scan result: writes the SSID into the draft (hidden networks
  /// are typed manually through the same field).
  void pickNetwork(ScanNetwork network) {
    final section = scanSection;
    if (section == null) return;
    final draft = drafts[section];
    if (draft == null) return;
    var next = applyFieldValue(draft, 'ssid', network.networkId);
    // halow entries may carry extension fields such as country (§9); only
    // apply them when the capability declares the field.
    final country = network.extras['country'];
    if (section == 'halow' && country is String) {
      final declared = _editingSectionFields['halow'] ?? const <String>[];
      if (declared.contains('country')) {
        next = applyFieldValue(next, 'country', country);
      }
    }
    updateDraft(next);
  }


  void _onPhaseChanged(SessionPhase phase) {
    if (phase == SessionPhase.scanning) _startScan();
    notifyListeners();
  }

  /// 进入扫描相位：新任务用新注册表；首个候选即离开扫描相位并停源。
  void _startScan() {
    _stopScanTasks();
    _registry = DiscoveryRegistry();
    _candidateSub = _source.candidates.listen((candidate) {
      _registry.absorb(candidate);
      if (_machine.phase == SessionPhase.scanning) {
        _machine.reportCandidate();
        // 出候选即停源（含扫描定时器）：用户挑选期间射频静默；选定
        // 候选时机器钩子会再停一次，停源幂等无副作用。
        unawaited(_stopSources());
      }
      notifyListeners();
    });
    unawaited(_startSourceGuarded());
    _scanTimer = Timer(scanTimeout, () {
      if (_machine.phase == SessionPhase.scanning) {
        _machine.reportScanTimeout();
        // 空结果同样回收底层资源（候选超时刷新验收点）。
        unawaited(_stopSources());
        notifyListeners();
      }
    });
    _sweepTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      // 候选超时刷新：超过 ttl 未再见到即移除（设备仍在广播会重新入表）。
      if (_registry.sweepExpired(DateTime.now(), ttl: ttl).isNotEmpty) {
        notifyListeners();
      }
    });
    notifyListeners();
  }

  /// 源启动失败（权限/射频在开扫瞬间变化）不外抛：立即按空结果收敛
  /// 并记录问题，不让界面悬在扫描态干等超时。
  Future<void> _startSourceGuarded() async {
    try {
      await _source.start();
    } catch (error) {
      if (_machine.phase == SessionPhase.scanning) {
        _stopScanTasks();
        _machine.reportProblem('source_start_failed', '$error');
        _machine.reportScanTimeout();
        notifyListeners();
      }
    }
  }

  /// 停止发现源与扫描定时器（注册表候选保留）。
  Future<void> _stopSources() async {
    _stopScanTasks();
    try {
      await _source.stop();
    } catch (_) {
      // 源可能未启动；停源幂等。
    }
  }

  void _stopScanTasks() {
    _candidateSub?.cancel();
    _candidateSub = null;
    _scanTimer?.cancel();
    _scanTimer = null;
    _sweepTimer?.cancel();
    _sweepTimer = null;
  }

  /// 断开链路并释放会话资源（幂等，供机器错误/清理路径调用）。
  Future<void> _releaseLink() async {
    final session = _session;
    _session = null;
    final channel = _channel;
    _channel = null;
    await session?.dispose();
    if (channel is UniversalCtGattChannel) {
      await channel.close();
    }
  }

  @override
  void dispose() {
    _stopScanTasks();
    _phaseSub.cancel();
    _problemSub.cancel();
    unawaited(_releaseLink());
    unawaited(_machine.dispose());
    super.dispose();
  }
}
