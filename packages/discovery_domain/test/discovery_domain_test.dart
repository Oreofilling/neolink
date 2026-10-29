import 'package:discovery_domain/discovery_domain.dart';
import 'package:test/test.dart';

void main() {
  test('发现通道与候选', () {
    expect(DiscoveryChannel.values.length, 3);
    const c = DiscoveryCandidate(
      candidateId: 't1', macSuffix: 'A1B2C3',
      channels: {DiscoveryChannel.ble}, provisionable: true, busy: false,
      lastSeen: _t,
    );
    expect(c.macSuffix, 'A1B2C3');
  });
}

final _t = DateTime(2026, 10, 29);
