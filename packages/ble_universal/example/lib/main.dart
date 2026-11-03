/// CT-Prov/1 真机 PoC 界面：扫描 → 点选设备 → §3 连接序列 →
/// device.info.get → session.close，每一步写入底部日志。
///
/// 运行前提：Windows 主机带蓝牙射频（内置或 USB dongle），设备端固件
/// 已进配置模式并按 §4.2 广播。
library;

import 'dart:async';

import 'package:ble_universal/ble_universal.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provisioning_session/provisioning_session.dart';
import 'package:universal_ble/universal_ble.dart';

void main(List<String> arguments) {
  runApp(CtProvPocApp(autoRun: arguments.contains('--auto')));
}

class CtProvPocApp extends StatelessWidget {
  const CtProvPocApp({super.key, this.autoRun = false});

  final bool autoRun;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CT-Prov PoC',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF2A4C0B)),
      home: PocHomePage(autoRun: autoRun),
    );
  }
}

class PocHomePage extends StatefulWidget {
  const PocHomePage({super.key, this.autoRun = false});

  final bool autoRun;

  @override
  State<PocHomePage> createState() => _PocHomePageState();
}

class _PocHomePageState extends State<PocHomePage> {
  final UniversalCtScanner _scanner = UniversalCtScanner();
  final Map<String, CtScanRecord> _devices = <String, CtScanRecord>{};
  final List<String> _log = <String>[];
  StreamSubscription<CtScanRecord>? _recordSub;
  StreamSubscription<BleDevice>? _rawSub;
  int _rawSeen = 0;
  bool _scanning = false;
  bool _busy = false;
  CtEnvironmentReport? _environment;

  @override
  void initState() {
    super.initState();
    // 启动即自检（SessionPhase.selfChecking 的入口动作）。
    unawaited(widget.autoRun ? _runAutomatic() : _selfCheck());
  }

  Future<void> _runAutomatic() async {
    await _selfCheck();
    if (!mounted) return;
    _appendLog('auto: scan and roundtrip enabled');
    await _toggleScan();
    if (!mounted || !_scanning) return;

    final deadline = DateTime.now().add(const Duration(seconds: 20));
    CtScanRecord? target;
    while (mounted && DateTime.now().isBefore(deadline)) {
      for (final record in _devices.values) {
        if (record.info.displayName?.startsWith('NE101-') ?? false) {
          target = record;
          break;
        }
      }
      if (target != null) break;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if (!mounted) return;
    if (target == null) {
      await _stopScan('auto: NE101 target not found');
      return;
    }
    _appendLog('auto: selected ${target.info.displayName}');
    await _runRoundtrip(target.deviceId);
  }

  Future<void> _selfCheck() async {
    final report = await UniversalCtEnvironment.probe();
    _appendLog('self-check: ${report.readiness.name} (${report.detail})');
    if (mounted) setState(() => _environment = report);
  }

  void _appendLog(String line) {
    if (!mounted) return;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      unawaited(kWindowsPairingChannel.invokeMethod<void>('log', line));
    }
    setState(() {
      _log.insert(0, line);
      if (_log.length > 200) _log.removeLast();
    });
  }

  Future<void> _toggleScan() async {
    if (_busy) return;
    if (_scanning) {
      await _stopScan('scan stopped');
      return;
    }
    setState(() => _scanning = true);
    // 扫描门禁：自检未通过先跑修复（授权/开射频），仍不通过则不启动。
    final environment = _environment;
    if (environment == null || !environment.canScan) {
      final report = await UniversalCtEnvironment.ensureReady();
      _appendLog('self-check: ${report.readiness.name} (${report.detail})');
      if (mounted) setState(() => _environment = report);
      if (!report.canScan) {
        setState(() => _scanning = false);
        _appendLog('scan aborted: environment not ready');
        return;
      }
    }
    _recordSub = _scanner.records.listen((record) {
      if (!_devices.containsKey(record.deviceId)) {
        _appendLog('found ${record.info.displayName}');
      }
      setState(() => _devices[record.deviceId] = record);
    });
    // 诊断：订阅 universal_ble 原始扫描流。前 30 条逐条打日志、其后每 50 条
    // 打一条，用于区分"插件没送达广播"还是"送达但 CT 解析失败"。
    _rawSeen = 0;
    _rawSub = UniversalBle.scanStream.listen((device) {
      _rawSeen++;
      if (_rawSeen <= 30 || _rawSeen % 50 == 0) {
        _appendLog(
          'raw#$_rawSeen: ${device.name ?? '(no name)'} '
          'id=${device.deviceId} rssi=${device.rssi} '
          'svcData=${device.serviceData.keys.toList()}',
        );
      }
    });
    try {
      await _scanner.start();
      _appendLog('scanning for CT-Prov service UUID...');
    } catch (error) {
      await _recordSub?.cancel();
      _recordSub = null;
      await _rawSub?.cancel();
      _rawSub = null;
      if (mounted) setState(() => _scanning = false);
      _appendLog('scan start failed: $error');
    }
  }

  /// 停止扫描并回收两侧订阅（toggle 停止与点选设备共用）。
  Future<void> _stopScan(String reason) async {
    await _scanner.stop();
    await _recordSub?.cancel();
    _recordSub = null;
    await _rawSub?.cancel();
    _rawSub = null;
    if (mounted) setState(() => _scanning = false);
    _appendLog(reason);
  }

  /// 对选中设备跑完一次 F1 往返：连接序列 → device.info.get →
  /// session.close → 断链。任何一步异常都记日志并确保链路回收。
  Future<void> _runRoundtrip(String deviceId) async {
    if (_busy) return;
    // 扫描中点选 = 已找到目标：先停扫再连接，否则只能静默忽略。
    if (_scanning) {
      await _stopScan('scan stopped (device selected)');
    }
    setState(() => _busy = true);
    final record = _devices[deviceId];
    _appendLog('connect ${record?.info.displayName ?? deviceId}');
    UniversalCtGattChannel? channel;
    try {
      // 先独立完成系统 bonding，再建立本应用的 GATT 会话（§4.4 桌面流）。
      // Windows 10 绕开 universal_ble 的 ProvidePin/自动保护等级分支，走
      // runner 原生通道的 ConfirmOnly + Encryption，并保留完整的
      // DevicePairingResultStatus（编排细节已下沉到 establishSystemBond）。
      await establishSystemBond(deviceId, onStep: _appendLog);

      // onStep：连接序列分步日志（连接/枚举/META/订阅/MTU/安全策略），
      // 异常前最后一条即失败点。
      channel = await UniversalCtGattChannel.open(deviceId, onStep: _appendLog);
      _appendLog(
        'connected, mtu=${channel.mtu}, '
        'meta name=${channel.meta?.name ?? '?'} '
        'busy=${channel.meta?.busy ?? '?'}',
      );

      final client = CtSessionClient(channel);
      try {
        await client.open();
        final info = await client.fetchDeviceInfo();
        _appendLog(
          'device.info: ${info.deviceName} / sn=${info.serialNumber} '
          '/ model=${info.model} / fw=${info.firmware} / '
          'power=${info.power.join('|')} / proto=v${info.protocolVersion}',
        );
        await client.closeSession();
        _appendLog('session.close ok');
      } finally {
        await client.dispose();
      }
    } catch (error) {
      _appendLog('roundtrip failed: $error');
    } finally {
      try {
        await channel?.close();
      } catch (error) {
        _appendLog('disconnect cleanup failed: $error');
      } finally {
        if (mounted) setState(() => _busy = false);
        _appendLog('disconnected');
      }
    }
  }

  @override
  void dispose() {
    unawaited(_recordSub?.cancel());
    unawaited(_rawSub?.cancel());
    unawaited(_scanner.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final devices = _devices.values.toList()
      ..sort((a, b) => (b.rssi ?? -999).compareTo(a.rssi ?? -999));
    return Scaffold(
      appBar: AppBar(
        title: const Text('CT-Prov PoC'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_scanning ? 'scanning' : 'idle'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          ListTile(
            dense: true,
            leading: Icon(switch (_environment?.readiness) {
              CtBleReadiness.ready => Icons.check_circle,
              CtBleReadiness.transient => Icons.hourglass_top,
              null => Icons.hourglass_top,
              _ => Icons.error_outline,
            }),
            title: Text('env: ${_environment?.readiness.name ?? 'checking'}'),
            subtitle: Text(_environment?.detail ?? 'probing...'),
            onTap: _busy ? null : _selfCheck,
          ),
          ListTile(
            leading: Icon(_scanning ? Icons.stop_circle : Icons.bluetooth),
            title: Text(_scanning ? 'Stop scan' : 'Start scan'),
            onTap: _toggleScan,
          ),
          const Divider(height: 1),
          Expanded(
            flex: 3,
            child: devices.isEmpty
                ? const Center(child: Text('No CT-Prov devices'))
                : ListView.builder(
                    itemCount: devices.length,
                    itemBuilder: (context, index) {
                      final record = devices[index];
                      final info = record.info;
                      return ListTile(
                        title: Text(info.displayName ?? record.deviceId),
                        subtitle: Text(
                          '${record.deviceId}  rssi=${record.rssi ?? '?'}  '
                          '${info.modelCodeName ?? 'unknown model'}',
                        ),
                        onTap: () => _runRoundtrip(record.deviceId),
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          Expanded(
            flex: 2,
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _log.length,
              itemBuilder: (context, index) => Text(
                _log[index],
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
