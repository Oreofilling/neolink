/// ct_disc_adapter tests: announce parsing against the NE301 wire format,
/// NIC classification heuristics, and the listener source driven through
/// an injected loopback socket (multicast itself only runs on real NICs).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ct_disc_adapter/ct_disc_adapter.dart';
import 'package:discovery_domain/discovery_domain.dart';
import 'package:test/test.dart';

const _announce = '{"type":"ct-announce","product":"NE301",'
    '"sn":"NE301202610270001","mac":"aa:bb:cc:84:c1:02","ip":"192.168.1.42",'
    '"fw":"1.8.0","port":80,"hw":"N6","caps":["wifi","cellular","poe"]}';

void main() {
  group('parseCtAnnounce', () {
    test('parses a real-shape NE301 announcement', () {
      final observation = parseCtAnnounce(utf8.encode(_announce));
      expect(observation, isNotNull);
      expect(observation!.macSuffix, '84C102');
      expect(observation.rawMac, 'aa:bb:cc:84:c1:02');
      expect(observation.product, 'NE301');
      expect(observation.ip, '192.168.1.42');
      expect(observation.port, 80);
      expect(observation.serialNumber, 'NE301202610270001');
      expect(observation.firmware, '1.8.0');
      expect(observation.capabilities, ['wifi', 'cellular', 'poe']);
    });

    test('rejects foreign and malformed datagrams', () {
      const ssdp =
          'NOTIFY * HTTP/1.1 HOST: 239.255.255.250:1900 NT: ssdp:alive';
      for (final payload in [
        ssdp,
        '{"type":"ssdp:alive"}', // wrong type on the shared group
        '{"type":"ct-announce","product":"NE301"}', // no mac/ip/port
        '{"type":"ct-announce","product":"NE301","mac":"not-a-mac",'
            '"ip":"1.2.3.4","port":80}',
        '{"type":"ct-announce","product":42,"mac":"aa:bb:cc:dd:ee:ff",'
            '"ip":"1.2.3.4","port":80}',
        '[1,2,3]', // not an object
        '',
      ]) {
        expect(parseCtAnnounce(utf8.encode(payload)), isNull, reason: payload);
      }
    });

    test('rejects non-UTF-8 bytes without throwing', () {
      expect(parseCtAnnounce([0xff, 0xfe, 0xfd]), isNull);
    });

    test('suffix is uppercase regardless of announce casing', () {
      final observation = parseCtAnnounce(
        utf8.encode(
          '{"type":"ct-announce","product":"NE301",'
          '"mac":"AA:BB:CC:BB:C6:DC","ip":"192.168.1.1","port":80}',
        ),
      );
      expect(observation!.macSuffix, 'BBC6DC');
    });
  });

  group('classifyNic', () {
    test('physical adapters stay physical', () {
      for (final name in ['Ethernet', 'WLAN', 'Wi-Fi', 'eno1', 'en0']) {
        expect(classifyNic(name), NicClass.physical, reason: name);
      }
    });

    test('VPN / container / virtual fragments are deprioritized', () {
      for (final name in [
        'vEthernet (Hyper-V)',
        'Tailscale',
        'ZeroTier One',
        'docker0',
        'tun0',
        'VMware Network Adapter VMnet1',
        'WSL',
        'VPNNic',
      ]) {
        expect(classifyNic(name), NicClass.virtualOrVpn, reason: name);
      }
    });
  });

  group('ctDiscCandidateFromObservation', () {
    test('candidate id encodes suffix and interface', () {
      final observation = parseCtAnnounce(utf8.encode(_announce))!;
      final candidate = ctDiscCandidateFromObservation(
        observation,
        interfaceName: 'Ethernet',
        now: () => DateTime(2026, 11, 5, 23, 30),
      );
      expect(candidate.candidateId, 'ctdisc:84C102@Ethernet');
      expect(candidate.macSuffix, '84C102');
      expect(candidate.modelHint, 'NE301');
      expect(candidate.channels, const {DiscoveryChannel.ctDisc});
      expect(candidate.provisionable, isTrue);
      expect(candidate.busy, isFalse);
    });
  });

  group('CtDiscDiscoverySource', () {
    test('announcements on the socket become candidates', () async {
      final loopbackSocket = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final source = CtDiscDiscoverySource(
        nicEnumerator: ({bool includeVirtual = false}) async => [
          NicEndpoint(
            interfaceName: 'lo0',
            address: InternetAddress.loopbackIPv4,
            nicClass: NicClass.physical,
          ),
        ],
        socketFactory: (names) async => loopbackSocket,
      );
      final received = <DiscoveryCandidate>[];
      final gotOne = Completer<void>();
      final sub = source.candidates.listen((candidate) {
        received.add(candidate);
        if (!gotOne.isCompleted) gotOne.complete();
      });
      await source.start();
      expect(source.joinedNics.single.interfaceName, 'lo0');

      final sender = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      sender.send(utf8.encode(_announce), InternetAddress.loopbackIPv4,
          loopbackSocket.port);
      await gotOne.future.timeout(const Duration(seconds: 5));
      await source.stop();
      await sub.cancel();
      sender.close();

      expect(received.single.macSuffix, '84C102');
      // Source address 127.0.0.1 /24-matches the lo0 endpoint.
      expect(received.single.candidateId, contains('@lo0'));
    });

    test('garbage datagrams are ignored without error', () async {
      final loopbackSocket = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final source = CtDiscDiscoverySource(
        nicEnumerator: ({bool includeVirtual = false}) async => [],
        socketFactory: (names) async => loopbackSocket,
      );
      final received = <DiscoveryCandidate>[];
      final sub = source.candidates.listen(received.add);
      await source.start();

      final sender = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      sender.send(
        utf8.encode('M-SEARCH * HTTP/1.1'),
        InternetAddress.loopbackIPv4,
        loopbackSocket.port,
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await source.stop();
      await sub.cancel();
      sender.close();

      expect(received, isEmpty);
    });

    test('stop clears join state; start is idempotent', () async {
      final loopbackSocket = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final source = CtDiscDiscoverySource(
        nicEnumerator: ({bool includeVirtual = false}) async => [],
        socketFactory: (names) async => loopbackSocket,
      );
      final sub = source.candidates.listen((_) {});
      await source.start();
      await source.start(); // second start must not rebind
      await source.stop();
      await sub.cancel();

      expect(source.joinedNics, isEmpty);
    });

    test('a failing socket factory leaves the channel silent', () async {
      final source = CtDiscDiscoverySource(
        nicEnumerator: ({bool includeVirtual = false}) async => [],
        socketFactory: (names) => throw const SocketException('no bind'),
      );
      final received = <DiscoveryCandidate>[];
      final sub = source.candidates.listen(received.add);
      await source.start(); // must not throw
      await source.stop();
      await sub.cancel();

      expect(received, isEmpty);
    });
  });

  group('enumerateNicEndpoints', () {
    test('returns IPv4 non-link-local endpoints or none, never throws',
        () async {
      final endpoints = await enumerateNicEndpoints();
      for (final endpoint in endpoints) {
        expect(endpoint.address.type, InternetAddressType.IPv4);
        expect(endpoint.address.address.startsWith('169.254.'), isFalse);
      }
    });

    test('includeVirtual adds vpn-like endpoints to the pool', () async {
      final physical = await enumerateNicEndpoints();
      final all = await enumerateNicEndpoints(includeVirtual: true);
      expect(all.length, greaterThanOrEqualTo(physical.length));
    });
  });
}
