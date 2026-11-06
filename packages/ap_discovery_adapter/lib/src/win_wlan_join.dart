/// Windows WLAN join primitives for the device softAP chain (M5 task 3).
///
/// Discovery sees the device AP; the softAP HTTP transport talks to it once
/// the machine's WLAN is associated with it. This file owns that middle
/// link: connect via a temporary open-network profile (no profile residue),
/// wait until the association is live and the device gateway answers TCP,
/// and restore whatever Wi-Fi link the machine had before the session.
///
/// Struct layouts mirror win_wlan.dart (both follow wlanapitypes.h; keep
/// them in sync). Polling model: WlanConnect is asynchronous, so the join
/// polls WlanQueryInterface(current_connection) for the association and a
/// plain TCP connect for gateway readiness — notification callbacks would
/// buy nothing at this cadence and cost NativeCallable plumbing.
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Overall join budget (association + DHCP + first gateway answer).
const Duration kDefaultJoinTimeout = Duration(seconds: 20);

/// Poll cadence while waiting for the association to come up.
const Duration _kAssocPollInterval = Duration(milliseconds: 300);

/// Poll cadence while waiting for the gateway to answer TCP.
const Duration _kGatewayPollInterval = Duration(milliseconds: 500);

/// Per-attempt TCP connect timeout for the gateway probe.
const Duration _kProbeTimeout = Duration(seconds: 1);

// wlan_interface_state_connected (wlanapitypes.h).
const int _kInterfaceStateConnected = 1;

// wlan_connection_mode_profile / wlan_connection_mode_temporary_profile.
const int _kConnectionModeProfile = 0;
const int _kConnectionModeTemporaryProfile = 2;

// dot11_BSS_type_infrastructure.
const int _kBssTypeInfrastructure = 1;

// wlan_intf_opcode_current_connection.
const int _kOpcodeCurrentConnection = 1;

/// The Wi-Fi link to return to after a softAP session.
final class WlanRestorePoint {
  const WlanRestorePoint({required this.ssid, this.profileName});

  /// SSID the machine was on before the join ('' when not connected).
  final String ssid;

  /// Saved profile name for that SSID; null when the machine had no
  /// profile-backed link (restore then just disconnects the device AP).
  final String? profileName;
}

/// Stable failure codes for [ApJoinException] (UI maps them to guidance).
const String kJoinNoInterface = 'no_wlan_interface';
const String kJoinConnectFailed = 'join_connect_failed';
const String kJoinTimeout = 'join_timeout';
const String kJoinGatewayTimeout = 'gateway_timeout';
const String kJoinRestoreFailed = 'restore_failed';

/// Join-chain failure with a stable [codeName] for UI mapping.
final class ApJoinException implements Exception {
  const ApJoinException(this.codeName, this.message);

  final String codeName;
  final String message;

  @override
  String toString() => 'ApJoinException($codeName): $message';
}

/// Minimal WLAN_PROFILE XML for an open infrastructure network.
///
/// Only used with the temporary-profile connection mode, so it never lands
/// in the profile store. SSIDs reaching here matched the device-AP pattern
/// (ASCII alnum/dash/underscore), but escaping keeps the generator honest.
String openNetworkProfileXml(String ssid) {
  final escaped = ssid
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
  return '<?xml version="1.0"?>'
      '<WLANProfile xmlns='
      '"http://www.microsoft.com/networking/WLAN/profile/v1">'
      '<name>$escaped</name>'
      '<SSIDConfig><SSID><name>$escaped</name></SSID></SSIDConfig>'
      '<connectionType>ESS</connectionType>'
      '<connectionMode>manual</connectionMode>'
      '<MSM><security><authEncryption>'
      '<authentication>open</authentication>'
      '<encryption>none</encryption>'
      '<useOneX>false</useOneX>'
      '</authEncryption></security></MSM>'
      '</WLANProfile>';
}

/// Join surface injected into the app controller (tests fake it).
abstract class ApJoiner {
  /// Remembers the machine's current Wi-Fi link, or null when there is
  /// nothing joinable (no WLAN interface / radio off / API refused).
  Future<WlanRestorePoint?> capture();

  /// Associates the machine's WLAN with the open device AP and waits until
  /// the device gateway answers TCP. Throws [ApJoinException] on failure.
  Future<void> join(
    String ssid, {
    Duration? timeout,
    String gatewayHost,
    int gatewayPort,
    void Function(String step)? onStep,
  });

  /// Returns to [point] (saved profile), or plain-disconnects the WLAN
  /// when the point carries no profile. Idempotent-safe; best effort.
  Future<void> restore(WlanRestorePoint? point);
}

/// wlanapi.dll implementation of [ApJoiner].
///
/// Methods are independent (open handle → act → close), mirroring
/// [WinWlanScanner]; the DLL resolves lazily so constructing on
/// non-Windows platforms is harmless and every method refuses early.
final class WinWlanJoiner implements ApJoiner {
  late final DynamicLibrary _wlanapi = DynamicLibrary.open('wlanapi.dll');
  late final _WlanOpenHandleDart _openHandle =
      _wlanapi.lookupFunction<_WlanOpenHandleNative, _WlanOpenHandleDart>(
          'WlanOpenHandle');
  late final _WlanEnumInterfacesDart _enumInterfaces = _wlanapi.lookupFunction<
      _WlanEnumInterfacesNative, _WlanEnumInterfacesDart>('WlanEnumInterfaces');
  late final _WlanConnectDart _connect = _wlanapi.lookupFunction<
      _WlanConnectNative, _WlanConnectDart>('WlanConnect');
  late final _WlanDisconnectDart _disconnect = _wlanapi.lookupFunction<
      _WlanDisconnectNative, _WlanDisconnectDart>('WlanDisconnect');
  late final _WlanQueryInterfaceDart _queryInterface = _wlanapi.lookupFunction<
      _WlanQueryInterfaceNative, _WlanQueryInterfaceDart>('WlanQueryInterface');
  late final _WlanFreeMemoryDart _freeMemory =
      _wlanapi.lookupFunction<_WlanFreeMemoryNative, _WlanFreeMemoryDart>(
          'WlanFreeMemory');
  late final _WlanCloseHandleDart _closeHandle =
      _wlanapi.lookupFunction<_WlanCloseHandleNative, _WlanCloseHandleDart>(
          'WlanCloseHandle');

  @override
  Future<WlanRestorePoint?> capture() {
    if (!Platform.isWindows) return Future.value();
    return _withFirstInterface<WlanCurrentConnection?>(
      _kInterfaceStateConnected,
      (handle, guid) async => _queryConnection(handle, guid),
    ).then((link) => link == null
        ? null
        : WlanRestorePoint(
            ssid: link.ssid,
            profileName: link.profileName.isEmpty ? null : link.profileName,
          ));
  }

  @override
  Future<void> join(
    String ssid, {
    Duration? timeout,
    String gatewayHost = '192.168.1.1',
    int gatewayPort = 80,
    void Function(String step)? onStep,
  }) async {
    if (!Platform.isWindows) {
      throw const ApJoinException(kJoinNoInterface, 'not running on Windows');
    }
    final budget = timeout ?? kDefaultJoinTimeout;
    final deadline = DateTime.now().add(budget);

    await _withFirstInterface<void>(_kAnyState, (handle, guid) async {
      onStep?.call('requesting wlan connect');
      final xml = openNetworkProfileXml(ssid).toNativeUtf16();
      final params = calloc<WlanConnectionParameters>();
      try {
        params.ref
          ..connectionMode = _kConnectionModeTemporaryProfile
          ..profile = xml.cast()
          ..dot11Ssid = nullptr
          ..desiredBssidList = nullptr
          ..bssType = _kBssTypeInfrastructure
          ..flags = 0;
        final rc = _connect(handle, guid, params, nullptr);
        if (rc != 0) {
          throw ApJoinException(kJoinConnectFailed, 'WlanConnect rc=$rc');
        }
      } finally {
        calloc
          ..free(params)
          ..free(xml);
      }

      // WlanConnect is asynchronous: poll the association by SSID. Matching
      // the SSID (not just the state) rules out "connected to something
      // else" — the auto-connect service may race us onto another network.
      onStep?.call('waiting association');
      var associated = false;
      while (!associated && DateTime.now().isBefore(deadline)) {
        final link = _queryConnection(handle, guid);
        if (link != null &&
            link.state == _kInterfaceStateConnected &&
            link.ssid == ssid) {
          associated = true;
        } else {
          await Future<void>.delayed(_kAssocPollInterval);
        }
      }
      if (!associated) {
        throw ApJoinException(kJoinTimeout, 'not associated with $ssid');
      }

      // DHCP runs after association; the operative readiness test is the
      // device actually answering on the gateway port (the same TCP path
      // the HTTP transport will use).
      onStep?.call('waiting gateway');
      var reachable = false;
      while (!reachable && DateTime.now().isBefore(deadline)) {
        reachable = await _probeGateway(gatewayHost, gatewayPort);
        if (!reachable) {
          await Future<void>.delayed(_kGatewayPollInterval);
        }
      }
      if (!reachable) {
        throw ApJoinException(
          kJoinGatewayTimeout,
          'gateway $gatewayHost:$gatewayPort did not answer',
        );
      }
    });
  }

  @override
  Future<void> restore(WlanRestorePoint? point) async {
    if (!Platform.isWindows) return;
    await _withFirstInterface<void>(_kAnyState, (handle, guid) async {
      final profile = point?.profileName;
      if (profile == null || profile.isEmpty) {
        final rc = _disconnect(handle, guid, nullptr);
        if (rc != 0) {
          throw ApJoinException(kJoinRestoreFailed, 'WlanDisconnect rc=$rc');
        }
        return;
      }
      final namePtr = profile.toNativeUtf16();
      final params = calloc<WlanConnectionParameters>();
      try {
        params.ref
          ..connectionMode = _kConnectionModeProfile
          ..profile = namePtr.cast()
          ..dot11Ssid = nullptr
          ..desiredBssidList = nullptr
          ..bssType = _kBssTypeInfrastructure
          ..flags = 0;
        final rc = _connect(handle, guid, params, nullptr);
        if (rc != 0) {
          throw ApJoinException(kJoinRestoreFailed, 'WlanConnect rc=$rc');
        }
      } finally {
        calloc
          ..free(params)
          ..free(namePtr);
      }
    });
  }

  /// One TCP connect to the device gateway; destroy keeps the probe
  /// connectionless (the HTTP transport opens its own).
  Future<bool> _probeGateway(String host, int port) async {
    try {
      final socket = await Socket.connect(host, port, timeout: _kProbeTimeout);
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  // Matches any interface state (join/restore entry points).
  static const int _kAnyState = -1;

  WlanCurrentConnection? _queryConnection(
    Pointer<Void> handle,
    Pointer<_JoinGuid> guid,
  ) {
    final dataSize = calloc<Uint32>();
    final data = calloc<Pointer<Void>>();
    final valueType = calloc<Uint32>();
    try {
      final rc = _queryInterface(
        handle,
        guid,
        _kOpcodeCurrentConnection,
        nullptr,
        dataSize,
        data,
        valueType,
      );
      if (rc != 0) return null;
      final attrs = data.value.cast<WlanConnectionAttributes>().ref;
      final link = WlanCurrentConnection(
        state: attrs.state,
        profileName: _fixedWideString(attrs.profileName),
        ssid: _fixedSsid(attrs.ssidLength, attrs.ssid),
      );
      _freeMemory(data.value);
      return link;
    } finally {
      calloc
        ..free(dataSize)
        ..free(data)
        ..free(valueType);
    }
  }

  /// Opens the WLAN API, enumerates interfaces, and runs [action] with the
  /// first interface's handle + GUID (single-WLAN machines are the norm;
  /// the scanner merges all interfaces the same way). [wantedState]
  /// pre-filters the interface state for capture callers (-1 accepts any).
  /// Throws [ApJoinException] with [kJoinNoInterface] when no WLAN
  /// interface exists; returns null when the state filter rejects it.
  Future<T> _withFirstInterface<T>(
    int wantedState,
    FutureOr<T> Function(Pointer<Void>, Pointer<_JoinGuid>) action,
  ) async {
    final negotiated = calloc<Uint32>();
    final handle = calloc<Pointer<Void>>();
    final interfaceList = calloc<Pointer<_JoinInterfaceInfoList>>();
    var handleOpen = false;
    try {
      if (_openHandle(2, nullptr, negotiated, handle) != 0) {
        throw const ApJoinException(kJoinNoInterface, 'WlanOpenHandle failed');
      }
      handleOpen = true;
      if (_enumInterfaces(handle.value, nullptr, interfaceList) != 0) {
        throw const ApJoinException(
          kJoinNoInterface,
          'WlanEnumInterfaces failed',
        );
      }
      final list = interfaceList.value.ref;
      if (list.numberOfItems == 0) {
        _freeMemory(interfaceList.value.cast<Void>());
        throw const ApJoinException(kJoinNoInterface, 'no WLAN interface');
      }
      final infoPtr = Pointer<_JoinInterfaceInfo>.fromAddress(
        interfaceList.value.address + _kListHeaderSize,
      );
      if (wantedState != _kAnyState && infoPtr.ref.state != wantedState) {
        _freeMemory(interfaceList.value.cast<Void>());
        return null as T;
      }
      // The GUID points into the interface-list memory: free it only after
      // the action completes (the action never holds the pointer past its
      // own return).
      final guid = infoPtr.cast<_JoinGuid>();
      try {
        return await action(handle.value, guid);
      } finally {
        _freeMemory(interfaceList.value.cast<Void>());
      }
    } finally {
      if (handleOpen) {
        _closeHandle(handle.value, nullptr);
      }
      calloc
        ..free(negotiated)
        ..free(handle)
        ..free(interfaceList);
    }
  }
}

/// Snapshot of WLAN_CONNECTION_ATTRIBUTES fields this package reads.
final class WlanCurrentConnection {
  const WlanCurrentConnection({
    required this.state,
    required this.profileName,
    required this.ssid,
  });

  /// wlan_interface_state_* value (1 = connected).
  final int state;

  /// Profile name backing the link ('' for temporary-profile links).
  final String profileName;

  /// Associated SSID ('' when not associated).
  final String ssid;
}

// ---- FFI shapes (wlanapitypes.h; public so tests can pin the layout) ----

const int _kListHeaderSize = 8;

final class _JoinGuid extends Struct {
  @Uint32()
  external int data1;
  @Uint16()
  external int data2;
  @Uint16()
  external int data3;
  @Array(8)
  external Array<Uint8> data4;
}

final class _JoinInterfaceInfo extends Struct {
  external _JoinGuid interfaceGuid;
  @Array(256)
  external Array<Uint16> description;
  @Uint32()
  external int state;
}

final class _JoinInterfaceInfoList extends Struct {
  @Uint32()
  external int numberOfItems;
  @Uint32()
  external int index;
  @Array(1)
  external Array<_JoinInterfaceInfo> interfaceInfo;
}

/// WLAN_CONNECTION_PARAMETERS (x64): mode@0, strProfile@8, pDot11Ssid@16,
/// pDesiredBssidList@24, dot11BssType@32, dwFlags@36 — sizeof 40. The two
/// pointer fields sit between the mode and the trailing enums exactly as
/// the header orders them; declaring them last keeps the tail packed.
final class WlanConnectionParameters extends Struct {
  @Uint32()
  external int connectionMode;
  external Pointer<Utf16> profile;
  external Pointer<Void> dot11Ssid;
  external Pointer<Void> desiredBssidList;
  @Uint32()
  external int bssType;
  @Uint32()
  external int flags;
}

/// WLAN_CONNECTION_ATTRIBUTES with the inline DOT11_SSID flattened:
/// isState@0, mode@4, strProfileName@8(512), ssidLength@520, ssid@524(32),
/// bssType@556, bssid@560(6), phyType@568, phyIndex@572, reason@576 —
/// sizeof 580.
final class WlanConnectionAttributes extends Struct {
  @Uint32()
  external int state;
  @Uint32()
  external int connectionMode;
  @Array(256)
  external Array<Uint16> profileName;
  @Uint32()
  external int ssidLength;
  @Array(32)
  external Array<Uint8> ssid;
  @Uint32()
  external int bssType;
  @Array(6)
  external Array<Uint8> bssid;
  @Uint32()
  external int phyType;
  @Uint32()
  external int phyIndex;
  @Uint32()
  external int reasonCode;
}

String _fixedWideString(Array<Uint16> chars) {
  var length = 0;
  while (length < 256 && chars[length] != 0) {
    length++;
  }
  final units = Uint16List(length);
  for (var i = 0; i < length; i++) {
    units[i] = chars[i];
  }
  return String.fromCharCodes(units);
}

String _fixedSsid(int lengthField, Array<Uint8> ssid) {
  final length = lengthField.clamp(0, 32);
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++) {
    bytes[i] = ssid[i];
  }
  return String.fromCharCodes(bytes);
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
  Pointer<Pointer<_JoinInterfaceInfoList>> interfaceList,
);
typedef _WlanEnumInterfacesDart = int Function(
  Pointer<Void> clientHandle,
  Pointer<Void> reserved,
  Pointer<Pointer<_JoinInterfaceInfoList>> interfaceList,
);

typedef _WlanConnectNative = Uint32 Function(
  Pointer<Void> clientHandle,
  Pointer<_JoinGuid> interfaceGuid,
  Pointer<WlanConnectionParameters> parameters,
  Pointer<Void> reserved,
);
typedef _WlanConnectDart = int Function(
  Pointer<Void> clientHandle,
  Pointer<_JoinGuid> interfaceGuid,
  Pointer<WlanConnectionParameters> parameters,
  Pointer<Void> reserved,
);

typedef _WlanDisconnectNative = Uint32 Function(
  Pointer<Void> clientHandle,
  Pointer<_JoinGuid> interfaceGuid,
  Pointer<Void> reserved,
);
typedef _WlanDisconnectDart = int Function(
  Pointer<Void> clientHandle,
  Pointer<_JoinGuid> interfaceGuid,
  Pointer<Void> reserved,
);

typedef _WlanQueryInterfaceNative = Uint32 Function(
  Pointer<Void> clientHandle,
  Pointer<_JoinGuid> interfaceGuid,
  Uint32 opcode,
  Pointer<Void> reserved,
  Pointer<Uint32> dataSize,
  Pointer<Pointer<Void>> data,
  Pointer<Uint32> valueType,
);
typedef _WlanQueryInterfaceDart = int Function(
  Pointer<Void> clientHandle,
  Pointer<_JoinGuid> interfaceGuid,
  int opcode,
  Pointer<Void> reserved,
  Pointer<Uint32> dataSize,
  Pointer<Pointer<Void>> data,
  Pointer<Uint32> valueType,
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
