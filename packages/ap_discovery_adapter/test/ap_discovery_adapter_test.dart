/// ap_discovery_adapter tests: SSID pattern recognition (spec + legacy
/// firmware forms), candidate normalization, and the polling source with
/// an injected scanner (FFI runs only on the Windows box).
library;

import 'dart:async';

import 'package:ap_discovery_adapter/ap_discovery_adapter.dart';
import 'package:discovery_domain/discovery_domain.dart';
import 'package:test/test.dart';

void main() {
  group('parseApSsid', () {
    test('spec CT-AP- form yields the MAC suffix without model hint', () {
      final info = parseApSsid('CT-AP-A1B2C3');
      expect(info?.macSuffix, 'A1B2C3');
      expect(info?.modelHint, isNull);
    });

    test('legacy firmware form yields suffix and family model hint', () {
      // Real NE101 on the bench tonight: family-suffixed model + suffix.
      final info = parseApSsid('NE101-P_BBC6DC');
      expect(info?.macSuffix, 'BBC6DC');
      expect(info?.modelHint, 'NE101');
    });

    test('plain model form yields the model as hint', () {
      final info = parseApSsid('NE301_84C102');
      expect(info?.macSuffix, '84C102');
      expect(info?.modelHint, 'NE301');
    });

    test('NE503 family and prefixed sub-models are accepted', () {
      expect(parseApSsid('NE503_A1B2C3')?.modelHint, 'NE503');
      // Prefix rule: a family-prefixed sub-model still starts with NE503.
      expect(parseApSsid('NE503C_A1B2C3')?.modelHint, 'NE503C');
    });

    test('non-device SSIDs are rejected', () {
      for (final ssid in [
        'Office-2.4G',
        'TP-LINK_5G',
        'Guest',
        'CT-AP-A1B2', // suffix too short
        'CT-AP-A1B2C3X', // suffix too long
        'CT-AP-A1B2CG', // not hex
        'ct-ap-a1b2c3', // case-sensitive: lowercase never matches
        'NE101-P-BBC6DC', // dash separator is the BLE name, not an SSID
        'X_A1B2C3', // model too short (1 char; minimum is 2)
        // Family whitelist: foreign <MODEL>_<SUFFIX> lookalikes are noise.
        'MYCAM_A1B2C3',
        'DEMO12_A1B2C3',
        'NE1_A1B2C3', // NE1 is not a product family
        '',
      ]) {
        expect(parseApSsid(ssid), isNull, reason: ssid);
      }
    });
  });

  group('apCandidatesFromNetworks', () {
    test('only device SSIDs become candidates with stable ids', () {
      final networks = [
        const WlanNetwork(
            ssid: 'Office-2.4G', signalQuality: 80, profileName: ''),
        const WlanNetwork(
            ssid: 'CT-AP-BBC6DC', signalQuality: 64, profileName: ''),
        const WlanNetwork(
            ssid: 'NE101-P_BBC6DC', signalQuality: 71, profileName: ''),
        // Whitelist: a pattern-shaped foreign SSID never becomes a row.
        const WlanNetwork(
            ssid: 'PRINTER_9F1D02', signalQuality: 90, profileName: ''),
      ];
      final fixedTime = DateTime(2026, 11, 5, 23, 0, 0);
      final candidates = apCandidatesFromNetworks(
        networks,
        now: () => fixedTime,
      );

      expect(candidates, hasLength(2));
      final spec = candidates[0];
      expect(spec.candidateId, 'ap:CT-AP-BBC6DC');
      expect(spec.macSuffix, 'BBC6DC');
      expect(spec.channels, const {DiscoveryChannel.accessPoint});
      expect(spec.provisionable, isTrue);
      expect(spec.busy, isFalse);
      expect(spec.lastSeen, fixedTime);
      // Signal is the quality/2-100 dBm estimate (display-grade).
      expect(spec.signal, -68);
      final legacy = candidates[1];
      expect(legacy.candidateId, 'ap:NE101-P_BBC6DC');
      expect(legacy.modelHint, 'NE101');
      expect(legacy.signal, -65); // 71/2-100 = -64.5 rounds away from zero
    });
  });

  group('ApDiscoverySource', () {
    test('start emits an immediate poll and keeps polling', () async {
      final source = ApDiscoverySource(
        scanner: () async => const [
          WlanNetwork(ssid: 'CT-AP-BBC6DC', signalQuality: 50, profileName: ''),
        ],
        pollInterval: const Duration(milliseconds: 30),
      );
      final received = <DiscoveryCandidate>[];
      final sub = source.candidates.listen(received.add);
      await source.start();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await source.stop();
      await sub.cancel();

      expect(received, isNotEmpty);
      expect(received.every((c) => c.macSuffix == 'BBC6DC'), isTrue);
    });

    test('stop cancels polling', () async {
      var scanCalls = 0;
      final source = ApDiscoverySource(
        scanner: () async {
          scanCalls++;
          return const [
            WlanNetwork(
                ssid: 'CT-AP-BBC6DC', signalQuality: 50, profileName: '')
          ];
        },
        pollInterval: const Duration(milliseconds: 20),
      );
      final sub = source.candidates.listen((_) {});
      await source.start();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await source.stop();
      final callsAtStop = scanCalls;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await sub.cancel();

      expect(callsAtStop, greaterThanOrEqualTo(1));
      expect(scanCalls, callsAtStop, reason: 'no polls after stop');
    });

    test('a refused scan (null) emits nothing and does not throw', () async {
      final source = ApDiscoverySource(
        scanner: () async => null,
        pollInterval: const Duration(milliseconds: 20),
      );
      final received = <DiscoveryCandidate>[];
      final sub = source.candidates.listen(received.add);
      await source.start();
      await Future<void>.delayed(const Duration(milliseconds: 70));
      await source.stop();
      await sub.cancel();

      expect(received, isEmpty);
    });

    test('a throwing scan cycle is swallowed; later cycles still run',
        () async {
      var calls = 0;
      final source = ApDiscoverySource(
        scanner: () async {
          calls++;
          if (calls == 1) throw StateError('wlan service down');
          return const [
            WlanNetwork(
                ssid: 'CT-AP-BBC6DC', signalQuality: 50, profileName: '')
          ];
        },
        pollInterval: const Duration(milliseconds: 20),
      );
      final received = <DiscoveryCandidate>[];
      final sub = source.candidates.listen(received.add);
      await source.start();
      await Future<void>.delayed(const Duration(milliseconds: 90));
      await source.stop();
      await sub.cancel();

      expect(calls, greaterThan(1));
      expect(received, isNotEmpty);
    });

    test('start is idempotent (one timer, one immediate poll)', () async {
      var calls = 0;
      final source = ApDiscoverySource(
        scanner: () async {
          calls++;
          return const <WlanNetwork>[];
        },
        pollInterval: const Duration(milliseconds: 200),
      );
      await source.start();
      await source.start();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await source.stop();

      expect(calls, 1);
    });
  });
}
