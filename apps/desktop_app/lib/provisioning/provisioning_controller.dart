/// 配置流程控制器（M2-4）：把统一状态机、发现注册表、发现源、环境
/// 探测与会话客户端组装成 UI 可订阅的 [ChangeNotifier]。
///
/// 页面不直接驱动状态机，也不直接触碰适配器；控制器是唯一编排点：
/// 迁移合法性由机器保证，控制器负责把异步链路结果翻译成机器事件，
/// 并对迟到事件按当前相位过滤（机器对非法迁移直接抛错）。
library;

import 'dart:async';

import 'package:ap_discovery_adapter/ap_discovery_adapter.dart';
import 'package:ble_universal/ble_universal.dart';
import 'package:communication_domain/communication_domain.dart';
import 'package:ct_disc_adapter/ct_disc_adapter.dart';
import 'package:flutter/foundation.dart';
// 能力侧的 ConfigSection 与 communication_domain 节类型重名：控制器
// 语境里 ConfigSection 一律指节草稿，能力节只经 capabilities.sections 迭代。
import 'package:provisioning_session/provisioning_session.dart'
    hide ConfigSection;

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
    Stream<bool> Function(String deviceId)? linkEvents,
    this.scanTimeout = const Duration(seconds: 20),
    this.ttl = const Duration(seconds: 12),
    this.selfCheckHold = const Duration(seconds: 5),
    this.sweepInterval = const Duration(seconds: 3),
  }) : _probe = environmentProbe ?? DesktopEnvironmentProbe(),
       // M5 default: the production app scans all three channels at once
       // (BLE first — the fast path users watch); tests inject their own
       // source and never touch this wiring.
       _source =
           discoverySource ??
           CompositeDiscoverySource([
             BleDiscoverySource(),
             ApDiscoverySource(),
             CtDiscDiscoverySource(),
           ]),
       _pair =
           establishPairing ?? ((deviceId) => establishSystemBond(deviceId)),
       _connect =
           connectChannel ??
           ((deviceId, onStep) =>
               UniversalCtGattChannel.open(deviceId, onStep: onStep)),
       _linkEvents = linkEvents ?? universalLinkEvents {
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

  /// 自检通过后的自动进入扫描倒计时（0 = 立即进入，测试用）。
  final Duration selfCheckHold;

  /// Sweep tick period for candidate expiry (shortened in tests).
  final Duration sweepInterval;

  final DesktopEnvironmentProbe _probe;
  final DiscoverySource _source;
  final Future<void> Function(String deviceId) _pair;
  final Future<CtGattChannel> Function(
    String deviceId,
    void Function(String step) onStep,
  )
  _connect;
  final Stream<bool> Function(String deviceId) _linkEvents;

  late final ProvisioningMachine _machine;
  late final StreamSubscription<SessionPhase> _phaseSub;
  late final StreamSubscription<SessionProblem> _problemSub;

  DiscoveryRegistry _registry = DiscoveryRegistry();
  // BLE platform device id per merge key (macSuffix). The registry keeps
  // the FIRST-seen candidateId across channels — when an AP sighting lands
  // before BLE, the merged row would otherwise carry the AP id into the
  // GATT chain. Cross-channel handles stay session-side (domain note).
  final Map<String, String> _bleDeviceIds = {};
  StreamSubscription<DiscoveryCandidate>? _candidateSub;
  Timer? _scanTimer;
  Timer? _sweepTimer;

  CtGattChannel? _channel;
  CtSessionClient? _session;

  /// Link-loss subscription (attached once capabilities are read;
  /// cancelled on drop/release).
  StreamSubscription<bool>? _linkSub;

  /// Reconnect attempt in flight (drives the modal button's busy state).
  bool get reconnecting => _reconnecting;
  bool _reconnecting = false;

  /// Last reconnect attempt failed (inline note in the modal; cleared
  /// before the next attempt).
  bool linkReconnectFailed = false;

  /// Drop happened while delivering (modal copy variant: guide toward
  /// idempotent redelivery).
  bool linkLostDuringDelivery = false;

  /// 自检结果（首次完成后保持，供各页展示通道状态）。
  EnvironmentCheckReport? environmentReport;

  /// 上次自检完成时刻（页面渲染「上次检测」戳——重检后行值可能不变，
  /// 时间戳证明检测确实跑过）。
  DateTime? selfCheckAt;

  /// 自检是否正在执行（页面骨架态）。
  bool get selfChecking => _selfChecking;
  bool _selfChecking = false;

  /// 自检通过后的倒计时剩余秒数（null = 未在倒计时：未开始/已停留/已进入）。
  int? selfCheckCountdown;

  /// 用户已选择停留在自检页（倒计时被取消，等待「立即扫描」）。
  bool get selfCheckHeld => _selfCheckHeld;
  bool _selfCheckHeld = false;
  Timer? _selfCheckTimer;

  /// Per-channel walk (v6): after the report lands the page reveals the
  /// channels one-by-one — this is the row currently being checked,
  /// -1 = no walk in flight.
  int selfCheckWalkIndex = -1;
  Timer? _walkTimer;
  Completer<void>? _walkCompleter;
  static const Duration _walkStep = Duration(milliseconds: 600);
  bool _disposed = false;

  /// 最近一次问题（连接/能力/下发失败与协议错误）。
  SessionProblem? lastProblem;

  /// 连接序列的分步进度（骨架屏进度行，最新在末尾）。
  final List<String> connectSteps = <String>[];

  /// Wall-clock stamp per [connectSteps] entry (v7d timeline: per-step
  /// elapsed shown beside each row — the diagnostic feel the connect page
  /// now goes for). Cleared alongside connectSteps.
  final List<DateTime> connectStepTimes = <DateTime>[];

  DiscoveryCandidate? selectedCandidate;
  DeviceInfoResult? deviceInfo;
  CapabilitiesResult? capabilities;

  /// MAC-suffix highlight set by the QR guide (row-level focus marker; the
  /// scan page paints the matching row, the guide itself stays UI-only).
  String? get qrFocusSuffix => _qrFocusSuffix;
  String? _qrFocusSuffix;

  /// Completed provisioning runs (in-memory receipts for the history page;
  /// persisted storage lands with a later milestone).
  List<SessionReceipt> get sessionHistory => _sessionHistory;
  final List<SessionReceipt> _sessionHistory = [];

  SessionPhase get phase => _machine.phase;
  List<DiscoveryCandidate> get candidates => _registry.snapshot;

  /// Same merge key the registry uses (macSuffix, else candidateId), so the
  /// BLE id lookup and the registry row always agree on identity.
  static String _mergeKeyOf(DiscoveryCandidate candidate) =>
      (candidate.macSuffix ?? candidate.candidateId).toUpperCase();

  /// NICs the CT-Disc listener joined (interface + subnet, §13.1: the user
  /// can see which sending interfaces are in play with VPN/virtual NICs
  /// around). Empty before the scan starts or with an injected source.
  List<String> get ctDiscNicLabels {
    DiscoverySource? source = _source;
    if (source is! CtDiscDiscoverySource &&
        source is CompositeDiscoverySource) {
      for (final child in source.sources) {
        if (child is CtDiscDiscoverySource) {
          source = child;
          break;
        }
      }
    }
    if (source is! CtDiscDiscoverySource) return const <String>[];
    return [
      for (final nic in source.joinedNics)
        if (nic.nicClass == NicClass.physical) nic.label,
    ];
  }

  /// Machine phase -> flow page id (the shell switches its workspace on
  /// this; v6 interaction: scan/results share one page, capabilities and
  /// form are one config page; v7c: an empty result stays on the scan page
  /// with the inline hint and the QR entry).
  String get pageForPhase => switch (_machine.phase) {
    SessionPhase.selfChecking => 'selfcheck',
    SessionPhase.scanning ||
    SessionPhase.resultsAvailable ||
    SessionPhase.guideScanning ||
    SessionPhase.showingGuide ||
    SessionPhase.scanEmpty => 'scan',
    SessionPhase.connecting ||
    SessionPhase.readingCapabilities ||
    SessionPhase.connectionError ||
    SessionPhase.capabilityError => 'connect',
    SessionPhase.choosingSections ||
    SessionPhase.editingConfig ||
    SessionPhase.delivering ||
    SessionPhase.operationError ||
    SessionPhase.linkLost => 'config',
    SessionPhase.completed => 'result',
    SessionPhase.cleaning => 'scan',
  };

  /// 环境自检（A2 修复：任意相位都可重新检测）。仍在自检相位时按结果驱动
  /// 状态机——通过则倒计时进入扫描（可停留），阻塞则停留本页；已离开自检
  /// 相位（中途回访）时只刷新报告，不迁移相位。
  Future<void> runSelfCheck() async {
    if (_selfChecking) return;
    _selfChecking = true;
    _cancelSelfCheckHold();
    notifyListeners();
    // The outer finally guarantees the in-flight flag resets even if the
    // probe layer ever throws — a stuck flag would silence the re-check
    // button forever (round-3 A2). It also spans the per-channel walk so a
    // walk cannot be re-entered while it plays.
    try {
      try {
        environmentReport = await _probe.probe();
      } finally {
        selfCheckAt = DateTime.now();
      }
      final report = environmentReport!;
      if (_machine.phase != SessionPhase.selfChecking) {
        notifyListeners();
        return;
      }
      if (!report.canProceed) {
        _selfCheckHeld = false;
        _machine.completeSelfCheck(
          canProceed: false,
          detail: report.channels
              .where((entry) => entry.capability != ChannelCapability.available)
              .map((entry) => '${entry.channel.name}: ${entry.reason}')
              .join(', '),
        );
        notifyListeners();
        return;
      }
      if (selfCheckHold == Duration.zero) {
        _selfCheckHeld = false;
        _machine.completeSelfCheck(canProceed: true);
        notifyListeners();
        return;
      }
      // v6 walk: reveal the channels one-by-one before arming the countdown;
      // await it so callers (and tests) observe a settled state afterwards.
      await _walkChannels(report.channels.length);
      // The walk can be cut short by a stay-click or a scan-now jump — only
      // arm the countdown while the page is still holding for it.
      if (_disposed) return;
      if (_selfCheckHeld || _machine.phase != SessionPhase.selfChecking) {
        notifyListeners();
        return;
      }
      selfCheckCountdown = selfCheckHold.inSeconds;
      _selfCheckHeld = false;
      notifyListeners();
      _selfCheckTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        final left = (selfCheckCountdown ?? 0) - 1;
        if (left <= 0) {
          startScanNow();
        } else {
          selfCheckCountdown = left;
          notifyListeners();
        }
      });
    } finally {
      _selfChecking = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Plays the one-by-one channel reveal (v6). Resolves when every row has
  /// been revealed — or early when the walk is cancelled (stay / scan-now /
  /// re-entry), so callers must re-check state after the await.
  Future<void> _walkChannels(int channelCount) async {
    if (channelCount <= 0) return;
    selfCheckWalkIndex = 0;
    notifyListeners();
    final walked = Completer<void>();
    _walkCompleter = walked;
    _walkTimer = Timer.periodic(_walkStep, (_) {
      final next = selfCheckWalkIndex + 1;
      if (next >= channelCount) {
        _cancelChannelWalk();
      } else {
        selfCheckWalkIndex = next;
        notifyListeners();
      }
    });
    await walked.future;
  }

  /// 停留自检页：取消倒计时与通道走查（A1：留时间检查环境与通道明细；
  /// v6：走查期间点击同样立即停留，通道全部展开为最终结果）。
  void stayOnSelfCheck() {
    if (selfCheckCountdown == null && selfCheckWalkIndex < 0) return;
    _cancelSelfCheckHold();
    _selfCheckHeld = true;
    notifyListeners();
  }

  /// 立即（或倒计时到点）进入扫描。
  void startScanNow() {
    if (_machine.phase != SessionPhase.selfChecking) return;
    _cancelSelfCheckHold();
    _selfCheckHeld = false;
    _machine.completeSelfCheck(canProceed: true);
    notifyListeners();
  }

  void _cancelSelfCheckHold() {
    _selfCheckTimer?.cancel();
    _selfCheckTimer = null;
    selfCheckCountdown = null;
    _cancelChannelWalk();
  }

  void _cancelChannelWalk() {
    _walkTimer?.cancel();
    _walkTimer = null;
    selfCheckWalkIndex = -1;
    final walked = _walkCompleter;
    _walkCompleter = null;
    if (walked != null && !walked.isCompleted) walked.complete();
  }

  /// 从候选列表选定设备：进入连接链（配对 → 通道 → 会话 → 读能力）。
  Future<void> selectCandidate(DiscoveryCandidate candidate) async {
    if (_machine.phase != SessionPhase.resultsAvailable) return;
    selectedCandidate = candidate;
    deviceInfo = null;
    capabilities = null;
    connectSteps.clear();
    connectStepTimes.clear();
    notifyListeners();
    await _machine.selectCandidate();
    await _connectChain(candidate);
  }

  Future<void> _connectChain(DiscoveryCandidate candidate) async {
    void onStep(String step) {
      connectSteps.add(step);
      connectStepTimes.add(DateTime.now());
      notifyListeners();
    }

    // Channel guard: only the BLE channel has a connect chain today. An
    // AP/CT-Disc-only row must fail with a stable reason instead of a
    // misleading GATT attempt (the softAP chain lands in its own round).
    if (!candidate.channels.contains(DiscoveryChannel.ble)) {
      if (_machine.phase == SessionPhase.connecting) {
        await _machine.failConnection('channel_unsupported', null);
        notifyListeners();
      }
      return;
    }
    // Merged rows keep the first-seen candidateId (possibly an AP id); the
    // GATT chain needs the platform device id from the BLE sighting.
    final deviceId =
        _bleDeviceIds[_mergeKeyOf(candidate)] ?? candidate.candidateId;

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
      // Link-loss detection starts here: failures during connect or the
      // capabilities read already have their own error pages; only a drop
      // inside the config session takes the linkLost modal path.
      _subscribeLink(deviceId);
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

  /// 连接/能力失败后原候选立即重试（NE101 断开后仍在配置模式，重试链
  /// 与首次选择完全一致）。
  Future<void> retryConnect() async {
    final candidate = selectedCandidate;
    if (candidate == null) return;
    if (_machine.phase != SessionPhase.connectionError &&
        _machine.phase != SessionPhase.capabilityError) {
      return;
    }
    _machine.switchCandidate();
    await selectCandidate(candidate);
  }

  // ---- link-loss detection (config session) ----

  /// Subscribe to link state (called once the link is up; cancels any
  /// previous subscription first — reused after reconnect).
  void _subscribeLink(String deviceId) {
    _linkSub?.cancel();
    _linkSub = _linkEvents(deviceId).listen(
      (connected) {
        if (!connected) _onLinkDropped();
      },
      onError: (Object _) {
        // Link-state reporting is best-effort: a failing stream never
        // blocks the session.
      },
    );
  }

  /// Link dropped: only reacts inside the config-session phases (a
  /// self-inflicted disconnect — session close / cleanup — has already
  /// left that group, so the event filters itself out). Drafts being
  /// edited are all kept.
  void _onLinkDropped() {
    switch (_machine.phase) {
      case SessionPhase.choosingSections:
      case SessionPhase.editingConfig:
      case SessionPhase.delivering:
      case SessionPhase.operationError:
        break;
      default:
        return;
    }
    linkLostDuringDelivery = _machine.phase == SessionPhase.delivering;
    _linkSub?.cancel();
    _linkSub = null;
    unawaited(_releaseLink());
    _machine.markLinkLost();
    _reconnecting = false;
    linkReconnectFailed = false;
    notifyListeners();
  }

  /// The modal's "reconnect": same chain as the initial selection
  /// (pair -> channel -> session -> device.info/capabilities). Success
  /// restores editing in place (drafts untouched); failure stays on the
  /// modal with a retry note. The device must be awake — the NE101 config
  /// window auto-sleeps after ~1 minute, so a burnt-out window is the most
  /// common drop cause and the copy must guide the wake-up.
  Future<void> reconnectLink() async {
    if (_machine.phase != SessionPhase.linkLost || _reconnecting) return;
    final candidate = selectedCandidate;
    if (candidate == null) return;
    _reconnecting = true;
    linkReconnectFailed = false;
    notifyListeners();
    try {
      final deviceId = candidate.candidateId;
      await _pair(deviceId);
      final channel = await _connect(deviceId, (_) {});
      _channel = channel;
      final session = CtSessionClient(channel);
      _session = session;
      await session.open();
      deviceInfo = await session.fetchDeviceInfo();
      capabilities = await session.fetchCapabilities();
      _subscribeLink(deviceId);
      _machine.linkRestored(editing: editingSections.isNotEmpty);
    } catch (error) {
      // A half-open failed link must still be cleaned up; the modal
      // stays and another attempt is allowed.
      await _releaseLink();
      linkReconnectFailed = true;
      _machine.reportProblem('link_reconnect_failed', '$error');
    } finally {
      _reconnecting = false;
      notifyListeners();
    }
  }

  /// QR guide: highlight the row whose MAC suffix was entered/parsed.
  void focusQrCandidate(String suffix) {
    final normalized = suffix.toUpperCase();
    if (_qrFocusSuffix == normalized) return;
    _qrFocusSuffix = normalized;
    notifyListeners();
  }

  /// Rescan from the empty/results page: releases link and sources, back
  /// to the scan loop. linkLost's "back to device list" exits here too —
  /// the editing round and drafts are dropped with it.
  Future<void> rescan() async {
    await _machine.cleanup();
    _clearEditingState();
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

  /// Cached config.get read-back for this editing round: modules opened
  /// later (one-module-at-a-time flow) prefill from the same snapshot
  /// without a second request.
  Map<String, Map<String, Object?>>? _storedConfig;

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
      name: capabilities!.sections
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

  /// Opens one section's module (one-module-at-a-time flow): the first open
  /// starts the editing round with just that section; later opens join the
  /// round in capability order, prefilled from the cached read-back. Drafts
  /// of already-open modules are never touched, so back-and-forth moves
  /// never lose entries. Reopening an open module is a pure view switch.
  Future<void> openSection(String name) async {
    final caps = capabilities;
    if (caps == null) return;
    final declared = caps.sections.any(
      (section) => section.name == name && section.configurable,
    );
    if (!declared) return;
    if (_machine.phase == SessionPhase.choosingSections) {
      await beginEditing({name});
      return;
    }
    if (_machine.phase != SessionPhase.editingConfig) return;
    if (editingSections.contains(name)) return;
    editingSections = [
      for (final section in caps.sections)
        if (section.configurable &&
            (editingSections.contains(section.name) || section.name == name))
          section.name,
    ];
    var draft = defaultSectionFor(name, declaredNetworks: declaredNetworks);
    final stored = _storedConfig?[name];
    if (stored != null) {
      draft = prefillSection(
        draft,
        stored,
        declaredFields: _editingSectionFields[name] ?? const [],
      );
    }
    drafts = {...drafts, name: draft};
    _validateSection(name);
    notifyListeners();
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
    _storedConfig = stored;
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
  ConfigPayload assembleDraftPayload() =>
      assembleConfigPayload(drafts, sectionFields: _editingSectionFields);

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
        for (final problem in payload.problems) problem.field: [problem],
      };
      notifyListeners();
      return;
    }

    _machine.beginDelivery();
    notifyListeners();
    try {
      deliveryResult = await session.setConfig(payload.payload);
      // The drop may land while config.set is in flight: linkLost owns
      // the UI by then, so the late result is discarded per the current
      // phase (idempotent redelivery overwrites everything; the receipt
      // is recorded after the redo succeeds).
      if (_machine.phase != SessionPhase.delivering) {
        deliveryResult = null;
        return;
      }
      _machine.deliveryStored();
      // Receipt for the history page: captured at the moment the device
      // confirmed persistence (before the session is closed).
      _sessionHistory.add(
        SessionReceipt(
          deviceName: deviceInfo?.deviceName ?? '',
          serialNumber: deviceInfo?.serialNumber ?? '',
          model: deviceInfo?.model ?? '',
          sections: List<String>.unmodifiable(deliveryResult!.stored),
          appliedAt: DateTime.now(),
        ),
      );
    } on ProvSessionException catch (error) {
      deliveryResult = null;
      if (_machine.phase == SessionPhase.delivering) {
        _machine.failOperation(error.reason, error.message);
      }
    } catch (error) {
      deliveryResult = null;
      if (_machine.phase == SessionPhase.delivering) {
        _machine.failOperation('config_set_failed', '$error');
      }
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
    _storedConfig = null;
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
    _syncSweepTimer(phase);
    notifyListeners();
  }

  /// 候选清扫计时器随相位：扫描/结果期保持运转。v6 连续扫描语义下两相
  /// 位都做超时淘汰（设备仍在广播会重新入表）；结果相位条目全部过期时
  /// 自动重开扫描窗口（cleanup → scanning），列表不会停在空快照上；时
  /// 龄标注的重绘也由本计时器驱动。
  void _syncSweepTimer(SessionPhase phase) {
    final active =
        phase == SessionPhase.scanning ||
        phase == SessionPhase.resultsAvailable;
    if (!active) {
      _sweepTimer?.cancel();
      _sweepTimer = null;
      return;
    }
    if (_sweepTimer != null) return;
    _sweepTimer = Timer.periodic(sweepInterval, (_) {
      if (_machine.phase == SessionPhase.scanning) {
        // 候选超时刷新：超过 ttl 未再见到即移除（设备仍在广播会重新入表）。
        if (_registry.sweepExpired(DateTime.now(), ttl: ttl).isNotEmpty) {
          notifyListeners();
        }
      } else if (_machine.phase == SessionPhase.resultsAvailable) {
        // 连续扫描：结果期同样按 ttl 淘汰；全部淘汰后重开扫描窗口。
        _registry.sweepExpired(DateTime.now(), ttl: ttl);
        if (_registry.snapshot.isEmpty) {
          unawaited(rescan());
          return;
        }
        notifyListeners();
      }
    });
  }

  /// 进入扫描相位：新任务用新注册表；连续扫描——出候选不停源，射频
  /// 持续静默监听，设备上线/下线直接反映在列表里（停源只发生在选定
  /// 候选、超时进入空态或会话清理时）。
  void _startScan() {
    _stopScanTasks();
    _registry = DiscoveryRegistry();
    _bleDeviceIds.clear();
    _qrFocusSuffix = null;
    _candidateSub = _source.candidates.listen((candidate) {
      _registry.absorb(candidate);
      if (candidate.channels.contains(DiscoveryChannel.ble)) {
        _bleDeviceIds[_mergeKeyOf(candidate)] = candidate.candidateId;
      }
      if (_machine.phase == SessionPhase.scanning) {
        _machine.reportCandidate();
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
  }

  /// Drops the link and releases session resources (idempotent; used by
  /// the machine's error/cleanup paths). Also stops the link listener —
  /// a self-initiated disconnect must not raise linkLost.
  Future<void> _releaseLink() async {
    _linkSub?.cancel();
    _linkSub = null;
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
    _disposed = true;
    _stopScanTasks();
    _sweepTimer?.cancel();
    _sweepTimer = null;
    _cancelSelfCheckHold();
    _linkSub?.cancel();
    _phaseSub.cancel();
    _problemSub.cancel();
    unawaited(_releaseLink());
    unawaited(_machine.dispose());
    super.dispose();
  }
}

/// One finished provisioning run — the receipt the history page renders.
/// Captured when the device confirms persistence (config.set stored).
final class SessionReceipt {
  const SessionReceipt({
    required this.deviceName,
    required this.serialNumber,
    required this.model,
    required this.sections,
    required this.appliedAt,
  });

  /// device.info device_name (e.g. "NE101-AABBCC").
  final String deviceName;

  /// device.info serial_number.
  final String serialNumber;

  /// device.info model.
  final String model;

  /// Section names the device reported as stored, in delivery order.
  final List<String> sections;

  /// Local wall-clock time of the confirmed delivery.
  final DateTime appliedAt;
}
