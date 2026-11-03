import 'dart:async';

import 'package:ble_universal/ble_universal.dart';
import 'package:desktop_app/services/environment_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseNetAdapters', () {
    test('多网卡数组输出', () {
      const jsonText =
          '[{"Name":"Wi-Fi","Status":"Up","PhysicalMediaType":"Native 802.11"},'
          '{"Name":"以太网","Status":"Disconnected","PhysicalMediaType":"802.3"}]';
      final adapters = parseNetAdapters(jsonText);

      expect(adapters, hasLength(2));
      expect(adapters![0].name, 'Wi-Fi');
      expect(adapters[0].status, 'Up');
      expect(adapters[0].mediaType, 'Native 802.11');
      expect(adapters[1].mediaType, '802.3');
    });

    test('单网卡时 ConvertTo-Json 输出对象而非数组', () {
      const jsonText =
          '{"Name":"Wi-Fi","Status":"Disabled","PhysicalMediaType":"Native 802.11"}';
      final adapters = parseNetAdapters(jsonText);

      expect(adapters, hasLength(1));
      expect(adapters!.single.status, 'Disabled');
    });

    test('不可解析输出返回 null', () {
      expect(parseNetAdapters('not json'), isNull);
    });
  });

  group('apChannelReadiness', () {
    NetAdapterInfo adapter({
      String mediaType = 'Native 802.11',
      String status = 'Up',
    }) => NetAdapterInfo(name: 'Wi-Fi', status: status, mediaType: mediaType);

    test('有已启用的无线网卡 → available', () {
      final entry = apChannelReadiness([
        adapter(mediaType: '802.3'),
        adapter(status: 'Disconnected'),
      ]);
      expect(entry.capability, ChannelCapability.available);
      expect(entry.reason, 'ready');
    });

    test('无线网卡全被禁用 → limited（可修复）', () {
      final entry = apChannelReadiness([adapter(status: 'Disabled')]);
      expect(entry.capability, ChannelCapability.limited);
      expect(entry.reason, 'wlan_disabled');
    });

    test('无无线网卡 → unavailable（呈现为能力限制）', () {
      final entry = apChannelReadiness([
        adapter(mediaType: '802.3', status: 'Up'),
      ]);
      expect(entry.capability, ChannelCapability.unavailable);
      expect(entry.reason, 'no_wlan_adapter');
    });

    test('探测失败（null）→ unavailable', () {
      final entry = apChannelReadiness(null);
      expect(entry.capability, ChannelCapability.unavailable);
      expect(entry.reason, 'adapter_probe_failed');
    });
  });

  group('DesktopEnvironmentProbe.probe', () {
    test('BLE 就绪 + 有无线网卡 → 可继续，三通道齐备', () async {
      final probe = DesktopEnvironmentProbe(
        probeBle: () async => const CtEnvironmentReport(
          readiness: CtBleReadiness.ready,
          detail: 'radio on',
        ),
        enumerateAdapters: () async => '[{"Name":"Wi-Fi","Status":"Up","PhysicalMediaType":"Native 802.11"}]',
      );

      final report = await probe.probe();

      expect(report.canProceed, isTrue);
      expect(
        report.channel(DiscoveryChannel.ble)?.capability,
        ChannelCapability.available,
      );
      expect(
        report.channel(DiscoveryChannel.accessPoint)?.capability,
        ChannelCapability.available,
      );
      // CT-Disc 本版预留：受限标注。
      expect(
        report.channel(DiscoveryChannel.ctDisc)?.capability,
        ChannelCapability.limited,
      );
    });

    test('AP 枚举受限但 BLE 可用仍可继续（验收：受限不是空列表）', () async {
      final probe = DesktopEnvironmentProbe(
        probeBle: () async => const CtEnvironmentReport(
          readiness: CtBleReadiness.ready,
          detail: 'radio on',
        ),
        enumerateAdapters: () async => null,
      );

      final report = await probe.probe();

      expect(report.canProceed, isTrue);
      final ap = report.channel(DiscoveryChannel.accessPoint)!;
      expect(ap.capability, ChannelCapability.unavailable);
      expect(ap.reason, 'adapter_probe_failed');
    });

    test('BLE 探测抛异常按 transient 降级，不牵连其余通道', () async {
      final probe = DesktopEnvironmentProbe(
        probeBle: () async => throw Exception('radio gone'),
        enumerateAdapters: () async => '[{"Name":"Wi-Fi","Status":"Up","PhysicalMediaType":"Native 802.11"}]',
      );

      final report = await probe.probe();

      final ble = report.channel(DiscoveryChannel.ble)!;
      expect(ble.capability, ChannelCapability.limited);
      expect(ble.reason, 'transient');
      expect(ble.detail, contains('radio gone'));
      expect(
        report.channel(DiscoveryChannel.accessPoint)?.capability,
        ChannelCapability.available,
      );
    });

    test('全部通道不可用 → 不可继续', () async {
      final probe = DesktopEnvironmentProbe(
        probeBle: () async => const CtEnvironmentReport(
          readiness: CtBleReadiness.poweredOff,
          detail: 'radio off',
        ),
        enumerateAdapters: () async => null,
      );

      final report = await probe.probe();

      expect(report.canProceed, isFalse);
    });

    // Round-3 A2: a wedged probe leg must resolve via the cap, not hang the
    // caller (the controller's in-flight flag would brick the re-check
    // button).
    test('a hung leg resolves as a degraded report after the cap', () async {
      final probe = DesktopEnvironmentProbe(
        probeBle: () => Completer<CtEnvironmentReport>().future,
        enumerateAdapters: () => Completer<String?>().future,
        legTimeout: const Duration(milliseconds: 50),
      );

      final report = await probe.probe();

      final ble = report.channel(DiscoveryChannel.ble)!;
      expect(ble.capability, ChannelCapability.limited);
      expect(ble.reason, 'transient');
      expect(ble.detail, contains('timed out'));
      expect(
        report.channel(DiscoveryChannel.accessPoint)?.reason,
        'adapter_probe_failed',
      );
    });
  });
}
