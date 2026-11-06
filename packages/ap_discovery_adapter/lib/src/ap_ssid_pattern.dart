/// Device AP SSID pattern parsing (product flow 5.2).
///
/// A device AP advertises `CT-AP-<MAC_SUFFIX>` where MAC_SUFFIX is the
/// last 3 bytes of the device canonical MAC in display order — the same
/// key the BLE advertisement carries, so the discovery registry can merge
/// the two channels. Shipping NE101 firmware still uses the legacy
/// `<MODEL>_<MAC_SUFFIX>` form (e.g. NE101-P_BBC6DC); both are accepted
/// until the CT-AP- rename lands (protocol doc section 16 note).
library;

/// Product families the AP scan provisions. Foreign SSIDs that happen to
/// fit the legacy `<MODEL>_<SUFFIX>` shape (a printer, a demo board) are
/// noise: the legacy form is only recognized when the model segment
/// starts with one of these families.
const List<String> kApModelPrefixes = ['NE101', 'NE301', 'NE503'];

/// Default device softAP address per family (factory config mode). The
/// CT-Prov HTTP binding is served on the device's own AP-side address,
/// which differs per model — NE101 and NE301 even sit in different /16s,
/// so a wrong pick never gets a TCP answer.
const Map<String, String> kApDefaultHostByModel = {
  'NE101': '192.168.1.1',
  'NE301': '192.168.10.10',
  'NE503': '10.0.0.1',
};

/// Resolves the softAP HTTP host for a candidate's model hint (family
/// prefix, e.g. "NE301" / "NE301-P"). A null or unrecognized hint (CT-AP-*
/// SSIDs carry no model) falls back to the NE101 address — the section 16
/// reference target.
String softapHostForModel(String? modelHint) {
  if (modelHint != null) {
    for (final family in kApModelPrefixes) {
      if (modelHint.startsWith(family)) return kApDefaultHostByModel[family]!;
    }
  }
  return kApDefaultHostByModel['NE101']!;
}

final RegExp _specSsid = RegExp(r'^CT-AP-([0-9A-F]{6})$');

// Legacy: the firmware emits `<MODEL>_<SUFFIX>` where MODEL may carry one
// family segment (NE101-P). Model charset matches the BLE name rules
// (2-10 uppercase alnum per segment, optional single dash segment).
final RegExp _legacySsid = RegExp(
  r'^([A-Z0-9]{2,10}(?:-[A-Z0-9]+)?)_([0-9A-F]{6})$',
);

/// Result of recognizing a device-AP SSID.
final class ApSsidInfo {
  const ApSsidInfo({required this.macSuffix, this.modelHint});

  /// Device canonical MAC suffix, 6 uppercase hex chars (merge key).
  final String macSuffix;

  /// Model family hint when the SSID carries one (legacy form only;
  /// CT-AP- SSIDs carry no model).
  final String? modelHint;
}

/// Recognizes a device-AP SSID; returns null for anything else (home
/// networks, neighbors, hidden/empty SSIDs, foreign `<MODEL>_<SUFFIX>`
/// lookalikes). SSIDs are case-sensitive bytes; device SSIDs are
/// uppercase by construction, so lowercase hex simply does not match.
ApSsidInfo? parseApSsid(String ssid) {
  final spec = _specSsid.firstMatch(ssid);
  if (spec != null) {
    return ApSsidInfo(macSuffix: spec.group(1)!);
  }
  final legacy = _legacySsid.firstMatch(ssid);
  if (legacy != null) {
    final model = legacy.group(1)!;
    // Family whitelist: only our product lines surface as candidates.
    if (!kApModelPrefixes.any(model.startsWith)) return null;
    // Family prefix (before any dash) is the model hint, matching how the
    // firmware derives the BLE device_name.
    final family = model.split('-').first;
    return ApSsidInfo(macSuffix: legacy.group(2)!, modelHint: family);
  }
  return null;
}
