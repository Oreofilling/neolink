/// CT-Prov/1 真机 PoC 界面：扫描 → 点选设备 → §3 连接序列 →
/// device.info.get → session.close，每一步写入底部日志。
///
/// 运行前提：Windows 主机带蓝牙射频（内置或 USB dongle），设备端固件
/// 已进配置模式并按 §4.2 广播。
library;

import 'dart:async';

import 'package:ble_universal/ble_universal.dart';
import 'package:flutter/material.dart';
import 'package:provisioning_session/provisioning_session.dart';

void main() {
  runApp(const CtProvPocApp());
}

class CtProvPocApp extends StatelessWidget {
  const CtProvPocApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CT-Prov PoC',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF2A4C0B)),
      home: const PocHomePage(),
    );
  }
}

class PocHomePage extends StatefulWidget {
  const PocHomePage({super.key});

  @override
  State<PocHomePage> createState() => _PocHomePageState();
}

class _PocHomePageState extends State<PocHomePage> {
  final UniversalCtScanner _scanner = UniversalCtScanner();
  final Map<String, CtScanRecord> _devices = <String, CtScanRecord>{};
  final List<String> _log = <String>[];
  StreamSubscription<CtScanRecord>? _recordSub;
  bool _scanning = false;
  bool _busy = false;

  void _appendLog(String line) {
    if (!mounted) return;
    setState(() {
      _log.insert(0, line);
      if (_log.length > 200) _log.removeLast();
    });
  }

  Future<void> _toggleScan() async {
    if (_busy) return;
    if (_scanning) {
      await _scanner.stop();
      await _recordSub?.cancel();
      _recordSub = null;
      setState(() => _scanning = false);
      _appendLog('scan stopped');
      return;
    }
    setState(() => _scanning = true);
    _recordSub = _scanner.records.listen((record) {
      if (!_devices.containsKey(record.deviceId)) {
        _appendLog('found ${record.info.displayName}');
      }
      setState(() => _devices[record.deviceId] = record);
    });
    try {
      await _scanner.start();
      _appendLog('scanning for CT-Prov service UUID...');
    } catch (error) {
      await _recordSub?.cancel();
      _recordSub = null;
      setState(() => _scanning = false);
      _appendLog('scan start failed: $error');
    }
  }

  /// 对选中设备跑完一次 F1 往返：连接序列 → device.info.get →
  /// session.close → 断链。任何一步异常都记日志并确保链路回收。
  Future<void> _runRoundtrip(String deviceId) async {
    if (_busy || _scanning) return;
    setState(() => _busy = true);
    final record = _devices[deviceId];
    _appendLog('connect ${record?.info.displayName ?? deviceId}');
    UniversalCtGattChannel? channel;
    try {
      channel = await UniversalCtGattChannel.open(deviceId);
      _appendLog('connected, mtu=${channel.mtu}, '
          'meta name=${channel.meta?.name ?? '?'} '
          'busy=${channel.meta?.busy ?? '?'}');

      final client = CtSessionClient(channel);
      try {
        await client.open();
        final info = await client.fetchDeviceInfo();
        _appendLog('device.info: ${info.deviceName} / sn=${info.serialNumber} '
            '/ model=${info.model} / fw=${info.firmware} / '
            'power=${info.power.join('|')} / proto=v${info.protocolVersion}');
        await client.closeSession();
        _appendLog('session.close ok');
      } finally {
        await client.dispose();
      }
    } catch (error) {
      _appendLog('roundtrip failed: $error');
    } finally {
      await channel?.close();
      if (mounted) setState(() => _busy = false);
      _appendLog('disconnected');
    }
  }

  @override
  void dispose() {
    unawaited(_recordSub?.cancel());
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
