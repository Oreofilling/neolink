/// CT-Disc discovery source: joins the announcement multicast group on
/// the allowed NICs and turns ct-announce datagrams into candidates
/// (product flow 5.3, NE301 ct_discover v1.0.0).
///
/// NE301's protocol is announce-only (a device beacon every 5 s; there is
/// no solicit to send), so the "broadcast" half of the plan's
/// broadcast/controlled-unicast wording reduces to joining and listening
/// for now. The candidate id encodes the receiving interface so a device
/// answering on two subnets stays visible on both (5.3: same response on
/// different NICs is displayed separately); the registry still merges by
/// MAC suffix across channels.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:discovery_domain/discovery_domain.dart';

import 'ct_announce.dart';
import 'nic_classifier.dart';

/// Multicast group announced by NE301 firmware (ct_discover.h).
const String kCtDiscMulticastGroup = '239.255.255.250';

/// Announcement port (ct_discover.h).
const int kCtDiscPort = 19850;

/// IPPROTO_IP / SOL_IP for the IPv4 membership socket option (identical
/// value 0 on Linux, Windows and macOS).
const int kIpProtoIpLevel = 0;

/// IP_ADD_MEMBERSHIP under BSD numbering (ws2ipdef.h on Windows,
/// netinet/in.h on macOS).
const int kIpAddMembershipBsd = 12;

/// IP_ADD_MEMBERSHIP under Linux (uapi/linux/in.h).
const int kIpAddMembershipLinux = 35;

/// Resolves the IP_ADD_MEMBERSHIP option number for [operatingSystem].
///
/// The option name is portable but the number is not: hardcoding one
/// platform's value fails setsockopt on the others (Windows answers
/// WSAENOPROTOOPT 10042), and a swallowed per-NIC failure turns that
/// into a silently dead channel.
int ipAddMembershipFor(String operatingSystem) =>
    operatingSystem == 'linux' ? kIpAddMembershipLinux : kIpAddMembershipBsd;

/// Normalizes one observation into a candidate.
///
/// The announce carries no busy flag, so busy=false / provisionable=true
/// — the session attempt is the arbiter, same as the AP channel.
DiscoveryCandidate ctDiscCandidateFromObservation(
  CtDiscObservation observation, {
  required String interfaceName,
  DateTime Function()? now,
}) {
  return DiscoveryCandidate(
    candidateId: 'ctdisc:${observation.macSuffix}@$interfaceName',
    macSuffix: observation.macSuffix,
    modelHint: observation.product,
    channels: const {DiscoveryChannel.ctDisc},
    provisionable: true,
    busy: false,
    lastSeen: (now ?? DateTime.now)(),
  );
}

/// Multicast listener source.
final class CtDiscDiscoverySource implements DiscoverySource {
  CtDiscDiscoverySource({
    Future<List<NicEndpoint>> Function({bool includeVirtual})? nicEnumerator,
    Future<RawDatagramSocket> Function(List<String> nicNames)? socketFactory,
    bool includeVirtualNics = false,
    DateTime Function()? now,
  })  : _nicEnumerator = nicEnumerator ?? enumerateNicEndpoints,
        _socketFactory = socketFactory,
        _includeVirtual = includeVirtualNics,
        _now = now;

  final Future<List<NicEndpoint>> Function({bool includeVirtual})
      _nicEnumerator;
  final Future<RawDatagramSocket> Function(List<String> nicNames)?
      _socketFactory;
  final bool _includeVirtual;
  final DateTime Function()? _now;

  final _candidates = StreamController<DiscoveryCandidate>.broadcast();
  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _socketSub;
  bool _starting = false;

  /// NICs currently joined (diagnostics + NIC picker state).
  List<NicEndpoint> joinedNics = const <NicEndpoint>[];

  /// Full endpoint pool used for source attribution; unlike [joinedNics]
  /// it keeps every address, so a multi-address NIC still labels
  /// announcements from any of its subnets.
  List<NicEndpoint> _attributionNics = const <NicEndpoint>[];

  @override
  Stream<DiscoveryCandidate> get candidates => _candidates.stream;

  @override
  Future<void> start() async {
    if (_socket != null || _starting) return;
    _starting = true;
    try {
      final nics = await _nicEnumerator(includeVirtual: _includeVirtual);
      final socket = await (_socketFactory?.call(
            nics.map((nic) => nic.interfaceName).toList(),
          ) ??
          _bindMulticast(nics));
      _socket = socket;
      _attributionNics = nics;
      // Factory-injected sockets bypass _bindMulticast's bookkeeping;
      // there the injected pool is the join seam, so report it as-is.
      if (_socketFactory != null) joinedNics = nics;
      _socketSub = socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram == null) return;
        final observation = parseCtAnnounce(datagram.data);
        if (observation == null) return;
        _candidates.add(
          ctDiscCandidateFromObservation(
            observation,
            interfaceName: _interfaceFor(datagram),
            now: _now,
          ),
        );
      });
    } catch (_) {
      // Bind failures (no NIC, sockets unavailable) leave the channel
      // silent; capability UI comes from the environment probe.
      _socket = null;
      joinedNics = const <NicEndpoint>[];
      _attributionNics = const <NicEndpoint>[];
    } finally {
      _starting = false;
    }
  }

  @override
  Future<void> stop() async {
    await _socketSub?.cancel();
    _socketSub = null;
    _socket?.close();
    _socket = null;
    joinedNics = const <NicEndpoint>[];
    _attributionNics = const <NicEndpoint>[];
  }

  /// Binds once and joins the group through every selected NIC.
  ///
  /// One membership per interface: a NIC holding several unicast
  /// addresses (secondary IPs) still gets a single join — a second
  /// membership for the same group and interface is redundant and
  /// Windows rejects it. [joinedNics] ends up holding only the NICs
  /// whose membership really took, so diagnostics never claim a join
  /// that setsockopt rejected.
  Future<RawDatagramSocket> _bindMulticast(List<NicEndpoint> nics) async {
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      kCtDiscPort,
      reuseAddress: true,
    );
    final group = InternetAddress(kCtDiscMulticastGroup);
    final joined = <NicEndpoint>[];
    final joinedInterfaces = <String>{};
    for (final endpoint in nics) {
      if (!joinedInterfaces.add(endpoint.interfaceName)) continue;
      try {
        _joinGroup(socket, group, endpoint.address);
        joined.add(endpoint);
      } catch (_) {
        // One unjoinable NIC (some VPN adapters refuse) must not take
        // down the whole channel; the rest keep listening.
      }
    }
    joinedNics = joined;
    return socket;
  }

  // Dart removed RawDatagramSocket.joinMulticastGroup; membership goes
  // through the raw IP_ADD_MEMBERSHIP socket option instead. The level
  // (IPPROTO_IP = 0) is portable, but the option NUMBER is not — see
  // ipAddMembershipFor. The payload is the 8-byte ip_mreq
  // {group, interface address}.
  static void _joinGroup(
    RawDatagramSocket socket,
    InternetAddress group,
    InternetAddress nicAddress,
  ) {
    final mreq = Uint8List(8)
      ..setAll(0, group.rawAddress.take(4).toList())
      ..setAll(4, nicAddress.rawAddress.take(4).toList());
    socket.setRawOption(
      RawSocketOption(
        kIpProtoIpLevel,
        ipAddMembershipFor(Platform.operatingSystem),
        mreq,
      ),
    );
  }

  /// Best-effort NIC attribution: prefer the joined NIC whose /24
  /// contains the datagram source, else the source address itself
  /// (diagnostics only — the candidate id stays stable per interface).
  String _interfaceFor(Datagram datagram) {
    for (final nic in _attributionNics) {
      if (_sameSubnet(nic.address, datagram.address)) {
        return nic.interfaceName;
      }
    }
    return datagram.address.address;
  }

  static bool _sameSubnet(InternetAddress nic, InternetAddress source) {
    final nicRaw = nic.rawAddress;
    final srcRaw = source.rawAddress;
    if (nicRaw.length != 4 || srcRaw.length != 4) return false;
    // /24 assumption is fine for attribution display: exactness is not
    // required, only a stable label.
    return nicRaw[0] == srcRaw[0] &&
        nicRaw[1] == srcRaw[1] &&
        nicRaw[2] == srcRaw[2];
  }
}
