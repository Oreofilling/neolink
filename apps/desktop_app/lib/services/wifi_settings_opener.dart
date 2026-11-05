/// "Guide the user to the system Wi-Fi page" (M5 task 1): opens the
/// Windows Wi-Fi settings page when the AP channel is limited because
/// the WLAN adapter is disabled. Injectable so widget tests observe
/// the launch without shelling out.
library;

import 'dart:io';

/// Launches the system Wi-Fi settings page; returns whether the launch
/// command succeeded.
typedef WifiSettingsOpener = Future<bool> Function();

/// Opens `ms-settings:network-wifi` through cmd `start`. Non-Windows
/// always reports false — there is no page to open.
Future<bool> openWifiSettings() async {
  if (!Platform.isWindows) return false;
  final result = await Process.run('cmd', const [
    '/c',
    'start',
    '',
    'ms-settings:network-wifi',
  ]);
  return result.exitCode == 0;
}
