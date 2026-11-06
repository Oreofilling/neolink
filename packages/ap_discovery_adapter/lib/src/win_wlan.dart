/// Windows WLAN API (wlanapi.dll) FFI bindings for SSID enumeration.
///
/// The plan calls for the platform network API (M5 task 1): netsh text
/// output is locale-dependent, so the native API is the only
/// locale-stable route on Windows. Everything here compiles on every
/// platform but only executes on Windows (guard lives in the discovery
/// source).
///
/// Scan model: WlanGetAvailableNetworkList returns the cache from the
/// OS's last scan; WlanScan triggers a fresh scan whose results land in
/// that cache a couple of seconds later. The polling source therefore
/// reads-then-triggers on every cycle.
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// One visible WLAN network from WlanGetAvailableNetworkList.
final class WlanNetwork {
  const WlanNetwork({
    required this.ssid,
    required this.signalQuality,
    required this.profileName,
  });

  /// Raw SSID bytes decoded as Latin-1 (device SSIDs are ASCII by
  /// construction); empty for hidden networks.
  final String ssid;

  /// 0-100 percentage (WLAN_SIGNAL_QUALITY). Raw value kept for
  /// diagnostics; the display uses [rssiEstimate].
  final int signalQuality;

  /// dBm estimate for the shared candidate signal field — the
  /// conventional quality/2-100 mapping (±3 dB, display-grade only: the
  /// four-bar reading and the dBm number tolerate that error).
  int get rssiEstimate => (signalQuality / 2 - 100).round();

  /// Profile name when the network is known/connected (diagnostics).
  final String profileName;
}

// wlanapi list structs follow wlanapitypes.h exactly: a two-DWORD
// header (dwNumberOfItems, dwIndex) followed by an INLINE struct
// array. No dwTotalSize (unlike most Win32 list structs) and no
// pointer array — a byte dump on the box confirmed the GUID bytes sit
// directly at offset 8. Walks use address arithmetic over the
// @Array(1) trailing members accordingly.
const int _kListHeaderSize = 8;

final class _Guid extends Struct {
  @Uint32()
  external int data1;
  @Uint16()
  external int data2;
  @Uint16()
  external int data3;
  @Array(8)
  external Array<Uint8> data4;
}

final class _WlanInterfaceInfo extends Struct {
  external _Guid interfaceGuid;
  @Array(256)
  external Array<Uint16> description;
  @Uint32()
  external int state;
}

final class _WlanInterfaceInfoList extends Struct {
  @Uint32()
  external int numberOfItems;
  @Uint32()
  external int index;
  @Array(1)
  external Array<_WlanInterfaceInfo> interfaceInfo;
}

final class _Dot11Ssid extends Struct {
  @Uint32()
  external int ssidLength;
  @Array(32)
  external Array<Uint8> ssid;
}

// Field order follows wlanapitypes.h exactly: strProfileName first,
// dwFlags last — a shifted layout reads plausible garbage (the first
// box smoke crashed on exactly that).
final class _WlanAvailableNetwork extends Struct {
  @Array(256)
  external Array<Uint16> profileName;
  external _Dot11Ssid dot11Ssid;
  @Uint32()
  external int bssType;
  @Uint32()
  external int numberOfBssids;
  @Uint32()
  external int connectable;
  @Uint32()
  external int notConnectableReason;
  @Uint32()
  external int numberOfPhyTypes;
  @Array(8)
  external Array<Uint32> phyTypes;
  @Uint32()
  external int morePhyTypes;
  @Uint32()
  external int signalQuality;
  @Uint32()
  external int securityEnabled;
  @Uint32()
  external int authAlgorithm;
  @Uint32()
  external int cipherAlgorithm;
  @Uint32()
  external int flags;
  @Uint32()
  external int reserved;
}

final class _WlanAvailableNetworkList extends Struct {
  @Uint32()
  external int numberOfItems;
  @Uint32()
  external int index;
  @Array(1)
  external Array<_WlanAvailableNetwork> network;
}

typedef _WlanOpenHandleNative = Uint32 Function(
  Uint32 clientVersion,
  Pointer<Void> reserved,
  Pointer<Uint32> negotiatedVersion,
  Pointer<Pointer<Void>> clientHandle,
);
typedef _WlanOpenHandleDart = int Function(
  int clientVersion,
  Pointer<Void> reserved,
  Pointer<Uint32> negotiatedVersion,
  Pointer<Pointer<Void>> clientHandle,
);

typedef _WlanEnumInterfacesNative = Uint32 Function(
  Pointer<Void> clientHandle,
  Pointer<Void> reserved,
  Pointer<Pointer<_WlanInterfaceInfoList>> interfaceList,
);
typedef _WlanEnumInterfacesDart = int Function(
  Pointer<Void> clientHandle,
  Pointer<Void> reserved,
  Pointer<Pointer<_WlanInterfaceInfoList>> interfaceList,
);

typedef _WlanScanNative = Uint32 Function(
  Pointer<Void> clientHandle,
  Pointer<_Guid> interfaceGuid,
  Pointer<Void> ssid,
  Pointer<Void> rawData,
  Pointer<Void> reserved,
);
typedef _WlanScanDart = int Function(
  Pointer<Void> clientHandle,
  Pointer<_Guid> interfaceGuid,
  Pointer<Void> ssid,
  Pointer<Void> rawData,
  Pointer<Void> reserved,
);

typedef _WlanGetAvailableNetworkListNative = Uint32 Function(
  Pointer<Void> clientHandle,
  Pointer<_Guid> interfaceGuid,
  Uint32 flags,
  Pointer<Void> reserved,
  Pointer<Pointer<_WlanAvailableNetworkList>> networkList,
);
typedef _WlanGetAvailableNetworkListDart = int Function(
  Pointer<Void> clientHandle,
  Pointer<_Guid> interfaceGuid,
  int flags,
  Pointer<Void> reserved,
  Pointer<Pointer<_WlanAvailableNetworkList>> networkList,
);

typedef _WlanFreeMemoryNative = Void Function(Pointer<Void> memory);
typedef _WlanFreeMemoryDart = void Function(Pointer<Void> memory);

typedef _WlanCloseHandleNative = Uint32 Function(
  Pointer<Void> clientHandle,
  Pointer<Void> reserved,
);
typedef _WlanCloseHandleDart = int Function(
  Pointer<Void> clientHandle,
  Pointer<Void> reserved,
);

String _wcharArray(Array<Uint16> chars, int length) {
  final units = Uint16List(length);
  for (var i = 0; i < length; i++) {
    units[i] = chars[i];
  }
  return String.fromCharCodes(units);
}

String _ssidBytes(_Dot11Ssid ssid) {
  final length = ssid.ssidLength.clamp(0, 32);
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++) {
    bytes[i] = ssid.ssid[i];
  }
  // Device SSIDs are ASCII (uppercase alnum, dash, underscore); Latin-1
  // decoding never mangles those and never throws.
  return String.fromCharCodes(bytes);
}

int _profileLength(_WlanAvailableNetwork raw) {
  var length = 0;
  while (length < 256 && raw.profileName[length] != 0) {
    length++;
  }
  return length;
}

/// Synchronous WLAN enumeration over wlanapi.dll.
///
/// One call = open handle, enumerate interfaces, read each interface's
/// cached scan, trigger a background rescan, close. Capability outcomes
/// (no adapter / radio off) surface one layer up in the discovery source;
/// this class reports them as null / empty.
///
/// The DLL and its symbols resolve lazily on first [scanOnce], so
/// constructing the scanner on a non-Windows platform (tests, CI) is
/// harmless — the platform guard lives in the discovery source.
final class WinWlanScanner {
  late final DynamicLibrary _wlanapi = DynamicLibrary.open('wlanapi.dll');
  late final _WlanOpenHandleDart _openHandle =
      _wlanapi.lookupFunction<_WlanOpenHandleNative, _WlanOpenHandleDart>(
          'WlanOpenHandle');
  late final _WlanEnumInterfacesDart _enumInterfaces = _wlanapi.lookupFunction<
      _WlanEnumInterfacesNative, _WlanEnumInterfacesDart>('WlanEnumInterfaces');
  late final _WlanScanDart _scan =
      _wlanapi.lookupFunction<_WlanScanNative, _WlanScanDart>('WlanScan');
  late final _WlanGetAvailableNetworkListDart _getNetworks =
      _wlanapi.lookupFunction<_WlanGetAvailableNetworkListNative,
          _WlanGetAvailableNetworkListDart>('WlanGetAvailableNetworkList');
  late final _WlanFreeMemoryDart _freeMemory =
      _wlanapi.lookupFunction<_WlanFreeMemoryNative, _WlanFreeMemoryDart>(
          'WlanFreeMemory');
  late final _WlanCloseHandleDart _closeHandle =
      _wlanapi.lookupFunction<_WlanCloseHandleNative, _WlanCloseHandleDart>(
          'WlanCloseHandle');

  /// Reads cached visible networks (all interfaces merged, deduped by
  /// SSID) and triggers a rescan for the next cycle. Returns null when
  /// the API refuses (no WLAN interface, radio off, service down).
  List<WlanNetwork>? scanOnce() {
    final negotiated = calloc<Uint32>();
    final handle = calloc<Pointer<Void>>();
    final interfaceList = calloc<Pointer<_WlanInterfaceInfoList>>();
    final networkList = calloc<Pointer<_WlanAvailableNetworkList>>();
    var handleOpen = false;
    try {
      if (_openHandle(
            2, // WLAN_CLIENT_VERSION_VISTA
            nullptr,
            negotiated,
            handle,
          ) !=
          0) {
        return null;
      }
      handleOpen = true;
      if (_enumInterfaces(handle.value, nullptr, interfaceList) != 0) {
        return null;
      }
      final list = interfaceList.value.ref;
      final count = list.numberOfItems;
      if (count == 0) {
        _freeMemory(interfaceList.value.cast<Void>());
        return const <WlanNetwork>[];
      }

      final seen = <String>{};
      final networks = <WlanNetwork>[];
      final ifBase = interfaceList.value.address + _kListHeaderSize;
      for (var i = 0; i < count; i++) {
        final infoPtr = Pointer<_WlanInterfaceInfo>.fromAddress(
            ifBase + i * sizeOf<_WlanInterfaceInfo>());
        // interfaceGuid is the first field (offset 0): the struct pointer
        // doubles as the GUID pointer.
        final guidPtr = infoPtr.cast<_Guid>();
        // Cached results of the previous scan first...
        if (_getNetworks(handle.value, guidPtr, 0, nullptr, networkList) == 0) {
          final scanned = networkList.value.ref;
          final netBase = networkList.value.address + _kListHeaderSize;
          for (var k = 0; k < scanned.numberOfItems; k++) {
            final raw = Pointer<_WlanAvailableNetwork>.fromAddress(
                    netBase + k * sizeOf<_WlanAvailableNetwork>())
                .ref;
            final ssid = _ssidBytes(raw.dot11Ssid);
            if (ssid.isEmpty || !seen.add(ssid)) continue;
            networks.add(WlanNetwork(
              ssid: ssid,
              signalQuality: raw.signalQuality,
              profileName: _wcharArray(raw.profileName, _profileLength(raw)),
            ));
          }
          _freeMemory(networkList.value.cast<Void>());
        }
        // ...then trigger the next scan (results land asynchronously).
        _scan(handle.value, guidPtr, nullptr, nullptr, nullptr);
      }
      _freeMemory(interfaceList.value.cast<Void>());
      return networks;
    } finally {
      if (handleOpen) {
        _closeHandle(handle.value, nullptr);
      }
      calloc
        ..free(negotiated)
        ..free(handle)
        ..free(interfaceList)
        ..free(networkList);
    }
  }
}
