/// Link-state bridge (loss detection): passes universal_ble's connection
/// event stream straight through.
///
/// A BLE link drop is detected by the link-layer supervision timer (the OS
/// keeps supervising once connected and raises ConnectionStatusChanged when
/// the peer goes silent); the plugin surfaces that as a per-device
/// true/false stream — detection costs zero application traffic and no
/// protocol change.
library;

import 'package:universal_ble/universal_ble.dart';

/// Connection events for [deviceId]: true = connected, false = dropped.
Stream<bool> universalLinkEvents(String deviceId) =>
    UniversalBle.connectionStream(deviceId);
