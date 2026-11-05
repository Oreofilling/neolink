/// ct-announce payload parsing (NE301 ct_discover v1.0.0 wire format).
///
/// Devices announce every 5 s on multicast 239.255.255.250:19850:
/// `{"type":"ct-announce","product","sn","mac","ip","fw","port","hw",
/// "caps":[...]}` — max 512 bytes. Only fields the discovery layer needs
/// are validated (type, mac); the rest pass through best-effort.
library;

import 'dart:convert';

/// One parsed announcement.
final class CtDiscObservation {
  const CtDiscObservation({
    required this.macSuffix,
    required this.rawMac,
    required this.product,
    required this.ip,
    required this.port,
    this.serialNumber,
    this.firmware,
    this.hardware,
    this.capabilities = const <String>[],
  });

  /// Device canonical MAC suffix, 6 uppercase hex chars (merge key with
  /// the BLE/AP channels).
  final String macSuffix;

  /// Raw MAC string as announced ("aa:bb:cc:dd:ee:ff").
  final String rawMac;

  /// Product/model name ("NE301"); model hint for the candidate.
  final String product;

  /// Device IPv4 address (for the future LAN transport handle).
  final String ip;

  /// Device service port (web API).
  final int port;

  final String? serialNumber;
  final String? firmware;
  final String? hardware;
  final List<String> capabilities;
}

final RegExp _macPattern = RegExp(
  r'^[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}$',
);

/// Parses one datagram payload; null when it is not a well-formed
/// ct-announce (foreign SSDP/mDNS traffic on the shared group, truncated
/// sends, future versions we do not understand yet).
CtDiscObservation? parseCtAnnounce(List<int> datagram) {
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(datagram));
  } on FormatException {
    return null;
  } on ArgumentError {
    return null; // invalid UTF-8
  }
  if (decoded is! Map) return null;
  if (decoded['type'] != 'ct-announce') return null;
  final mac = decoded['mac'];
  final product = decoded['product'];
  if (mac is! String || !_macPattern.hasMatch(mac) || product is! String) {
    return null;
  }
  final ip = decoded['ip'];
  final port = decoded['port'];
  if (ip is! String || port is! int) return null;

  final octets = mac.split(':');
  final suffix = '${octets[3]}${octets[4]}${octets[5]}'.toUpperCase();

  final caps = decoded['caps'];
  return CtDiscObservation(
    macSuffix: suffix,
    rawMac: mac.toLowerCase(),
    product: product,
    ip: ip,
    port: port,
    serialNumber: decoded['sn'] is String ? decoded['sn'] as String : null,
    firmware: decoded['fw'] is String ? decoded['fw'] as String : null,
    hardware: decoded['hw'] is String ? decoded['hw'] as String : null,
    capabilities: caps is List && caps.every((c) => c is String)
        ? List<String>.from(caps)
        : const <String>[],
  );
}
