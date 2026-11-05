/// Device AP discovery source: polls WLAN SSID enumeration and emits
/// candidates for SSIDs matching the device-AP pattern (product flow 5.2).
///
/// Channel capability (no WLAN adapter / radio off) is decided by the
/// environment probe, not here: a scanner returning null (API refused)
/// simply emits nothing for that cycle — an empty capability-limited
/// state must never masquerade as "no devices" (acceptance 13.1).
library;

import 'dart:async';
import 'dart:io';

import 'package:discovery_domain/discovery_domain.dart';

import 'ap_ssid_pattern.dart';
import 'win_wlan.dart';

/// Poll cadence. Each cycle reads the cached scan and triggers the next
/// one, so the effective latency is up to two intervals; the device AP
/// stays up for the whole config-mode window, so seconds-level cadence is
/// fine (BLE drives the fast path).
const Duration kApPollInterval = Duration(seconds: 8);

/// Normalizes one WLAN scan into candidates.
///
/// [now] is injectable for tests. AP observations cannot see the CT-Prov
/// BUSY flag (an SSID carries no payload), so busy=false /
/// provisionable=true — the session attempt itself is the arbiter.
List<DiscoveryCandidate> apCandidatesFromNetworks(
  List<WlanNetwork> networks, {
  DateTime Function()? now,
}) {
  final timestamp = (now ?? DateTime.now)();
  return [
    for (final network in networks)
      if (parseApSsid(network.ssid) case final info?)
        DiscoveryCandidate(
          candidateId: 'ap:${network.ssid}',
          macSuffix: info.macSuffix,
          modelHint: info.modelHint,
          channels: const {DiscoveryChannel.accessPoint},
          provisionable: true,
          busy: false,
          lastSeen: timestamp,
        ),
  ];
}

/// Polling discovery source over WLAN SSID enumeration.
final class ApDiscoverySource implements DiscoverySource {
  ApDiscoverySource({
    Future<List<WlanNetwork>?> Function()? scanner,
    Duration pollInterval = kApPollInterval,
    DateTime Function()? now,
  })  : _scanner = scanner,
        _pollInterval = pollInterval,
        _now = now;

  final Future<List<WlanNetwork>?> Function()? _scanner;
  WinWlanScanner? _winScanner;
  final Duration _pollInterval;
  final DateTime Function()? _now;

  final _candidates = StreamController<DiscoveryCandidate>.broadcast();
  Timer? _timer;
  bool _scanning = false;

  @override
  Stream<DiscoveryCandidate> get candidates => _candidates.stream;

  @override
  Future<void> start() async {
    if (_timer != null) return;
    _timer = Timer.periodic(_pollInterval, (_) => _poll());
    _poll();
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _poll() async {
    // Never overlap polls: a slow WLAN call just skips a beat.
    if (_scanning) return;
    _scanning = true;
    try {
      final networks = await _resolveScanner()();
      if (networks == null) return;
      for (final candidate in apCandidatesFromNetworks(networks, now: _now)) {
        _candidates.add(candidate);
      }
    } catch (_) {
      // A failed poll cycle is not a channel verdict; the next cycle
      // retries. Capability states come from the environment probe.
    } finally {
      _scanning = false;
    }
  }

  Future<List<WlanNetwork>?> Function() _resolveScanner() {
    final injected = _scanner;
    if (injected != null) return injected;
    // Non-Windows platforms have no device-AP enumeration path (mobile OS
    // limits are the documented case): report nothing rather than crash
    // on a missing DLL. The platform check runs before the lazy scanner
    // ever touches wlanapi.dll.
    return () async {
      if (!Platform.isWindows) return const <WlanNetwork>[];
      return (_winScanner ??= WinWlanScanner()).scanOnce();
    };
  }
}
