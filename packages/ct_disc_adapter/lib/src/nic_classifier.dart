/// NIC enumeration and classification for the CT-Disc channel
/// (product flow 5.3: record which interface an answer came from, and
/// deprioritize VPN / container / virtual adapters by default).
library;

import 'dart:io';

/// Coarse NIC class for join decisions and UI priority.
enum NicClass {
  /// Physical adapter (joined by default).
  physical,

  /// VPN / container / bridged virtual adapter (skipped by default;
  /// selectable explicitly in the NIC picker).
  virtualOrVpn,

  /// Loopback and link-local only (never joined).
  internal,
}

/// Name fragments that mark an adapter as virtual/VPN. Matched
/// case-insensitively against the OS interface name.
const List<String> kVirtualNicFragments = [
  'tun', // WireGuard/OpenVPN TUN
  'tap', // OpenVPN TAP
  'vpn',
  'ppp',
  'vmware',
  'vmnet',
  'virtualbox',
  'veth',
  'docker',
  'vbr',
  'hyper-v',
  'vethernet', // Windows Hyper-V virtual switch
  'wsl',
  'loopback',
  'isatap',
  'teredo',
  'tailscale',
  'zerotier',
];

/// Classifies one interface name.
NicClass classifyNic(String name) {
  final lowered = name.toLowerCase();
  for (final fragment in kVirtualNicFragments) {
    if (lowered.contains(fragment)) return NicClass.virtualOrVpn;
  }
  return NicClass.physical;
}

/// One joinable multicast endpoint: an IPv4 address on a named NIC.
final class NicEndpoint {
  const NicEndpoint({
    required this.interfaceName,
    required this.address,
    required this.nicClass,
  });

  final String interfaceName;
  final InternetAddress address;
  final NicClass nicClass;

  /// Display label for the NIC picker: name + address + class marker
  /// (acceptance 13.1 "user can see the sending interface and subnet").
  String get label => '$interfaceName (${address.address})';
}

/// Enumerates IPv4 NIC endpoints, excluding loopback unless asked.
///
/// [includeVirtual] adds VPN/container adapters — the NIC picker's
/// explicit override path; the default join set stays physical-only.
Future<List<NicEndpoint>> enumerateNicEndpoints({
  bool includeVirtual = false,
}) async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
  );
  return [
    for (final nic in interfaces)
      for (final address in nic.addresses)
        if (_usable(address))
          NicEndpoint(
            interfaceName: nic.name,
            address: address,
            nicClass: classifyNic(nic.name),
          ),
  ]
      .where(
        (endpoint) => includeVirtual || endpoint.nicClass == NicClass.physical,
      )
      .toList();
}

bool _usable(InternetAddress address) {
  // Skip link-local (169.254.x.x) and wildcard entries: they cannot carry
  // useful subnet information for the picker.
  final raw = address.rawAddress;
  return !(raw[0] == 169 && raw[1] == 254);
}
