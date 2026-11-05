// Tier-3 device-in-the-loop probe: drives the PRODUCTION controller (real
// BLE adapters, real GATT, real firmware) headlessly through the full
// provisioning chain, N times, on the bench's RTL8761B dongle.
//
// Modes (NL_PROBE_MODE): "detect" (default) only checks whether a CT-Prov
// device is advertising — it always passes and prints a marker for the
// verify script; "full" runs the loop and fails on any deviation.
// NL_PROBE_CYCLES sets the loop count (default 3). NL_PROBE_KILL_AT
// ("editing") drops the host side of the link mid-edit and proves the
// v7c in-place recovery on real hardware.
//
// Wake discipline: the NE101 sleeps ~62s after the config key is pressed.
// A batch needs one press; if the device drops out mid-run the probe stops
// with a "not advertising" failure naming the cycle — that is the signal
// to press the key and rerun.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provisioning_session/provisioning_session.dart'
    hide ConfigSection;

import 'package:ble_universal/ble_universal.dart';
import 'package:communication_domain/communication_domain.dart';
import 'package:desktop_app/provisioning/provisioning_controller.dart';
import 'package:desktop_app/provisioning/section_editing.dart';

const _probeSsid = 'neolink-probe';

Future<bool> _waitFor(
  bool Function() condition,
  Duration limit,
  String what,
) async {
  final deadline = DateTime.now().add(limit);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  // ignore: avoid_print, terminal marker is parsed by tool/verify.ps1
  print('PROBE_TIMEOUT waiting for: $what');
  return false;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final mode = Platform.environment['NL_PROBE_MODE'] ?? 'detect';
  final cycles = int.parse(Platform.environment['NL_PROBE_CYCLES'] ?? '3');
  final killAt = Platform.environment['NL_PROBE_KILL_AT'] ?? 'none';

  testWidgets('real device probe ($mode, cycles=$cycles, killAt=$killAt)', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final watch = Stopwatch()..start();
      void mark(String line) {
        // ignore: avoid_print, terminal markers are parsed by verify.ps1
        print('PROBE $watch $line');
      }

      // Production wiring: no injected fakes, the real adapters.
      final controller = ProvisioningController(
        selfCheckHold: Duration.zero,
        scanTimeout: const Duration(seconds: 25),
      );
      addTearDown(controller.dispose);

      await controller.runSelfCheck();
      if (!await _waitFor(
        () => controller.phase == SessionPhase.scanning,
        const Duration(seconds: 20),
        'scanning phase',
      )) {
        fail('self-check never reached scanning: ${controller.phase}');
      }
      // The production source now scans all three channels at once; this
      // probe drives the BLE chain, so "a device" means a BLE candidate.
      if (!await _waitFor(
        () => controller.candidates.any(
          (candidate) => candidate.channels.contains(DiscoveryChannel.ble),
        ),
        const Duration(seconds: 15),
        'first BLE advertisement',
      )) {
        mark('RESULT=no-device');
        if (mode == 'full') {
          fail('no CT-Prov advertisement — wake the device and rerun');
        }
        return; // detect mode: absence is a SKIP, not a failure
      }
      final found = controller.candidates.firstWhere(
        (candidate) => candidate.channels.contains(DiscoveryChannel.ble),
      );
      mark(
        'RESULT=device-found id=${found.candidateId} '
        'model=${found.modelHint} mac=${found.macSuffix}',
      );
      if (mode == 'detect') return;

      for (var cycle = 1; cycle <= cycles; cycle++) {
        final cycleWatch = Stopwatch()..start();

        // Fresh candidate for this cycle (the device re-advertises after
        // session close; the registry may still hold the old entry).
        if (controller.candidates.isEmpty) {
          unawaited(controller.rescan());
          if (!await _waitFor(
            () => controller.candidates.isNotEmpty,
            const Duration(seconds: 20),
            'advertisement in cycle $cycle',
          )) {
            fail(
              'cycle $cycle: device not advertising anymore '
              '(deep sleep hit?) — press the config key and rerun',
            );
          }
        }
        final candidate = controller.candidates.firstWhere(
          (entry) => entry.provisionable,
          orElse: () => controller.candidates.first,
        );

        await controller.selectCandidate(candidate);
        if (!await _waitFor(
          () => controller.phase == SessionPhase.choosingSections,
          const Duration(seconds: 30),
          'connect + capabilities in cycle $cycle',
        )) {
          fail(
            'cycle $cycle: stuck at ${controller.phase} '
            '(${controller.lastProblem?.reason ?? 'no problem'})',
          );
        }

        await controller.openSection('wifi');
        if (!await _waitFor(
          () => controller.phase == SessionPhase.editingConfig,
          const Duration(seconds: 10),
          'editing phase in cycle $cycle',
        )) {
          fail('cycle $cycle: never entered editing (${controller.phase})');
        }
        final draft = controller.drafts['wifi'];
        if (draft == null) {
          fail('cycle $cycle: no wifi draft after openSection');
        }
        // Constant ssid on purpose: repeated identical config.set writes
        // are the idempotency claim the M6 gate has to stand behind.
        controller.updateDraft(applyFieldValue(draft, 'ssid', _probeSsid));

        if (killAt == 'editing') {
          mark('cycle $cycle: injecting host-side link drop');
          await forceLinkDown(candidate.candidateId);
          if (!await _waitFor(
            () => controller.phase == SessionPhase.linkLost,
            const Duration(seconds: 15),
            'linkLost in cycle $cycle',
          )) {
            fail('cycle $cycle: link drop not detected (${controller.phase})');
          }
          controller.reconnectLink();
          if (!await _waitFor(
            () =>
                controller.phase == SessionPhase.editingConfig &&
                !controller.reconnecting,
            const Duration(seconds: 30),
            'reconnect in cycle $cycle',
          )) {
            fail('cycle $cycle: reconnect did not restore editing');
          }
          if (_ssidOf(controller.drafts['wifi']) != _probeSsid) {
            fail('cycle $cycle: draft ssid lost across reconnect');
          }
        }

        await controller.submit();
        if (!await _waitFor(
          () => controller.phase == SessionPhase.completed,
          const Duration(seconds: 30),
          'config.set stored in cycle $cycle',
        )) {
          fail(
            'cycle $cycle: deliver stuck at ${controller.phase} '
            '(${controller.lastProblem?.reason ?? 'no problem'})',
          );
        }
        final stored = controller.deliveryResult?.stored ?? const <String>[];
        if (!stored.contains('wifi')) {
          fail('cycle $cycle: wifi not in stored sections: $stored');
        }
        if (controller.sessionHistory.length != cycle) {
          fail(
            'cycle $cycle: history has ${controller.sessionHistory.length} '
            'receipts, expected $cycle',
          );
        }
        mark('CYCLE $cycle PASS in ${cycleWatch.elapsed.inSeconds}s');

        unawaited(controller.finishSession());
        // finishSession goes completed -> cleaning -> scanning, and the
        // scan loop may re-find the still-advertising device (or report
        // empty) before a poll lands on the transient scanning phase.
        // Any post-cleanup phase proves the session closed.
        if (!await _waitFor(
          () =>
              controller.phase == SessionPhase.scanning ||
              controller.phase == SessionPhase.resultsAvailable ||
              controller.phase == SessionPhase.scanEmpty,
          const Duration(seconds: 15),
          'session close in cycle $cycle',
        )) {
          fail('cycle $cycle: session never closed (${controller.phase})');
        }
      }

      mark('RESULT=all-pass cycles=$cycles');
    });
  }, timeout: const Timeout(Duration(minutes: 20)));
}

/// ssid off any wifi draft (the field accessor works on every section
/// shape, so the probe stays decoupled from the concrete section classes).
String? _ssidOf(Object? draft) {
  if (draft is! ConfigSection) return null;
  final value = fieldValue(draft, 'ssid');
  return value is String ? value : null;
}
