import 'package:discovery_domain/discovery_domain.dart';
import 'package:test/test.dart';

void main() {
  final t0 = DateTime(2026, 11, 3, 12, 0, 0);

  DiscoveryCandidate bleCandidate(
    String? macSuffix, {
    String candidateId = 'dev-1',
    DateTime? lastSeen,
    bool busy = false,
    bool provisionable = true,
    int? signal = -55,
    String? modelHint = 'NE101',
  }) => DiscoveryCandidate(
    candidateId: candidateId,
    macSuffix: macSuffix,
    modelHint: modelHint,
    channels: const {DiscoveryChannel.ble},
    provisionable: provisionable,
    busy: busy,
    lastSeen: lastSeen ?? t0,
    signal: signal,
  );

  test('发现通道枚举为三路', () {
    expect(DiscoveryChannel.values.length, 3);
  });

  group('DiscoveryRegistry 跨通道合并', () {
    test('同 macSuffix 两条记录合并为一条，取较晚时间与最近信号', () {
      final registry = DiscoveryRegistry();
      registry.absorb(bleCandidate('A1B2C3', signal: -55));
      registry.absorb(
        bleCandidate(
          'a1b2c3',
          lastSeen: t0.add(const Duration(seconds: 3)),
          signal: -70,
        ),
      );

      expect(registry.snapshot, hasLength(1));
      final merged = registry.snapshot.single;
      expect(merged.lastSeen, t0.add(const Duration(seconds: 3)));
      expect(merged.signal, -70);
      expect(merged.candidateId, 'dev-1');
    });

    test('不同 macSuffix 保持独立条目', () {
      final registry = DiscoveryRegistry();
      registry.absorb(bleCandidate('A1B2C3', candidateId: 'dev-1'));
      registry.absorb(bleCandidate('84C102', candidateId: 'dev-2'));

      expect(registry.snapshot, hasLength(2));
      expect(registry.snapshot.map((c) => c.macSuffix).toSet(), {
        'A1B2C3',
        '84C102',
      });
    });

    test('macSuffix 缺失时按 candidateId 独立成条', () {
      final registry = DiscoveryRegistry();
      registry.absorb(bleCandidate(null, candidateId: 'dev-1'));
      registry.absorb(bleCandidate(null, candidateId: 'dev-2'));

      expect(registry.snapshot, hasLength(2));
    });

    test('最近记录忙时强制不可配置（§4.2.2）', () {
      final registry = DiscoveryRegistry();
      registry.absorb(bleCandidate('A1B2C3', provisionable: true));
      registry.absorb(
        bleCandidate(
          'A1B2C3',
          lastSeen: t0.add(const Duration(seconds: 1)),
          busy: true,
          provisionable: false,
        ),
      );

      final merged = registry.snapshot.single;
      expect(merged.busy, isTrue);
      expect(merged.provisionable, isFalse);
    });

    test('modelHint 与 signal 取首见/最近非空值', () {
      final registry = DiscoveryRegistry();
      registry.absorb(bleCandidate('A1B2C3', modelHint: 'NE101', signal: -50));
      registry.absorb(
        bleCandidate(
          'A1B2C3',
          lastSeen: t0.add(const Duration(seconds: 1)),
          modelHint: null,
          signal: null,
        ),
      );

      final merged = registry.snapshot.single;
      expect(merged.modelHint, 'NE101');
      expect(merged.signal, -50);
    });

    test('updates 流发出每次合并后的候选', () async {
      final registry = DiscoveryRegistry();
      // 先订阅再驱动：广播流事件异步投递，事后 listen 会漏事件。
      final emittedFuture = registry.updates.take(2).toList();
      registry.absorb(bleCandidate('A1B2C3'));
      registry.absorb(
        bleCandidate('A1B2C3', lastSeen: t0.add(const Duration(seconds: 2))),
      );
      final emitted = await emittedFuture;

      expect(emitted, hasLength(2));
      expect(emitted.last.lastSeen, t0.add(const Duration(seconds: 2)));
    });
  });

  group('DiscoveryRegistry 超时淘汰', () {
    test('只淘汰超过 ttl 的候选并返回被移除项', () {
      final registry = DiscoveryRegistry();
      registry.absorb(bleCandidate('A1B2C3', lastSeen: t0));
      registry.absorb(
        bleCandidate('84C102', lastSeen: t0.add(const Duration(seconds: 20))),
      );

      final removed = registry.sweepExpired(
        t0.add(const Duration(seconds: 30)),
        ttl: const Duration(seconds: 25),
      );

      expect(removed.map((c) => c.macSuffix), ['A1B2C3']);
      expect(registry.snapshot, hasLength(1));
      expect(registry.snapshot.single.macSuffix, '84C102');
    });

    test('重新出现的候选不被淘汰', () {
      final registry = DiscoveryRegistry();
      registry.absorb(
        bleCandidate('A1B2C3', lastSeen: t0.add(const Duration(seconds: 40))),
      );

      final removed = registry.sweepExpired(
        t0.add(const Duration(seconds: 50)),
      );
      expect(removed, isEmpty);
      expect(registry.snapshot, hasLength(1));
    });
  });
}
