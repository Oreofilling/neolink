import 'package:ble_universal/src/environment_check.dart';
import 'package:test/test.dart';
import 'package:universal_ble/universal_ble.dart';

void main() {
  group('ctReadinessFrom', () {
    test('poweredOn is ready when permission is granted or not required', () {
      expect(
        ctReadinessFrom(AvailabilityState.poweredOn),
        CtBleReadiness.ready,
      );
      expect(
        ctReadinessFrom(AvailabilityState.poweredOn, permissionGranted: true),
        CtBleReadiness.ready,
      );
    });

    test('missing permission wins over radio state', () {
      expect(
        ctReadinessFrom(AvailabilityState.poweredOn, permissionGranted: false),
        CtBleReadiness.unauthorized,
      );
      expect(
        ctReadinessFrom(AvailabilityState.poweredOff, permissionGranted: false),
        CtBleReadiness.unauthorized,
      );
    });

    test('radio states map to actionable verdicts', () {
      expect(
        ctReadinessFrom(AvailabilityState.poweredOff),
        CtBleReadiness.poweredOff,
      );
      expect(
        ctReadinessFrom(AvailabilityState.unauthorized),
        CtBleReadiness.unauthorized,
      );
      expect(
        ctReadinessFrom(AvailabilityState.unsupported),
        CtBleReadiness.unsupported,
      );
    });

    test('unknown and resetting stay transient', () {
      expect(
        ctReadinessFrom(AvailabilityState.unknown),
        CtBleReadiness.transient,
      );
      expect(
        ctReadinessFrom(AvailabilityState.resetting),
        CtBleReadiness.transient,
      );
    });
  });

  test('CtEnvironmentReport.canScan only for ready', () {
    for (final readiness in CtBleReadiness.values) {
      final report = CtEnvironmentReport(readiness: readiness, detail: 'x');
      expect(report.canScan, readiness == CtBleReadiness.ready);
    }
  });
}
