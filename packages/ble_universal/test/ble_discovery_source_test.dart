import 'package:ble_universal/ble_universal.dart';
import 'package:discovery_domain/discovery_domain.dart';
import 'package:test/test.dart';

void main() {
  final t0 = DateTime(2026, 11, 3, 12, 0, 0);

  CtScanRecord record({
    String deviceId = '9C:13:9E:BB:C6:DE',
    int? rssi = -48,
    String? macSuffix = 'A1B2C3',
    String? modelCodeName = 'NE101',
    bool? busy = false,
    bool? provisionable = true,
    bool payloadFieldsReliable = true,
  }) => CtScanRecord(
    deviceId: deviceId,
    rssi: rssi,
    info: CtDiscoveredDevice(
      formatVersion: 1,
      formatVersionSupported: true,
      payloadFieldsReliable: payloadFieldsReliable,
      modelCode: 0x01,
      modelCodeName: modelCodeName,
      macSuffix: macSuffix,
      busy: busy,
      provisionable: provisionable,
    ),
  );

  test('可靠负载全字段映射', () {
    final candidate = bleCandidateFromRecord(record(), now: () => t0);

    expect(candidate.candidateId, '9C:13:9E:BB:C6:DE');
    expect(candidate.macSuffix, 'A1B2C3');
    expect(candidate.modelHint, 'NE101');
    expect(candidate.channels, {DiscoveryChannel.ble});
    expect(candidate.busy, isFalse);
    expect(candidate.provisionable, isTrue);
    expect(candidate.signal, -48);
    expect(candidate.lastSeen, t0);
  });

  test('已知忙时强制不可配置（§4.2.2）', () {
    final candidate = bleCandidateFromRecord(
      record(busy: true, provisionable: false),
      now: () => t0,
    );

    expect(candidate.busy, isTrue);
    expect(candidate.provisionable, isFalse);
  });

  test('负载不可靠时标志缺失按可继续取向且 macSuffix 置空', () {
    final candidate = bleCandidateFromRecord(
      record(
        macSuffix: null,
        modelCodeName: null,
        busy: null,
        provisionable: null,
        payloadFieldsReliable: false,
      ),
      now: () => t0,
    );

    expect(candidate.macSuffix, isNull);
    expect(candidate.modelHint, isNull);
    expect(candidate.busy, isFalse);
    expect(candidate.provisionable, isTrue);
  });

  test('macSuffix 归一为大写', () {
    final candidate = bleCandidateFromRecord(
      record(macSuffix: 'a1b2c3'),
      now: () => t0,
    );

    expect(candidate.macSuffix, 'A1B2C3');
  });

  group('BLE 通道就绪映射（M2-3）', () {
    ChannelReadiness map(CtBleReadiness readiness) => bleChannelReadiness(
      CtEnvironmentReport(readiness: readiness, detail: 'diag'),
    );

    test('ready → available，reason 沿用枚举名', () {
      final entry = map(CtBleReadiness.ready);
      expect(entry.channel, DiscoveryChannel.ble);
      expect(entry.capability, ChannelCapability.available);
      expect(entry.reason, 'ready');
      expect(entry.detail, 'diag');
    });

    test('transient → limited（稍后重检可恢复）', () {
      expect(
        map(CtBleReadiness.transient).capability,
        ChannelCapability.limited,
      );
    });

    test('射频关/未授权/不支持 → unavailable', () {
      expect(
        map(CtBleReadiness.poweredOff).capability,
        ChannelCapability.unavailable,
      );
      expect(
        map(CtBleReadiness.unauthorized).capability,
        ChannelCapability.unavailable,
      );
      expect(
        map(CtBleReadiness.unsupported).capability,
        ChannelCapability.unavailable,
      );
    });
  });
}
