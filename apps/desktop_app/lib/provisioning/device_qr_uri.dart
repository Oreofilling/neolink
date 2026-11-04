/// Strict parser for the `ctdev://` device-guide QR URI.
///
/// Grammar (firmware docs/CT_DEVICE_QR_SPEC.md §2-§6):
///
///     ctdev://guide-v1/<MAC_SUFFIX>?m=<MODEL>&c=<CHANNELS>&g=<GUIDE_ID>
///
/// Parsing is intentionally unforgiving: scheme/authority are the exact
/// lowercase literals, the path is a single segment of 6 uppercase hex
/// characters, the query carries exactly the m/c/g fields (no duplicates,
/// no unknown keys, none missing), a fragment is forbidden, and the whole
/// URI is limited to 128 bytes of printable ASCII with no percent-encoding.
/// The QR content is a *hint* that speeds up device lookup — anything that
/// does not match is rejected so a smudged or foreign QR can never steer
/// the app, and the manual suffix input stays the fallback.
library;

/// Channel bits of the `c` field bitmap (§4.3).
const int kQrChannelBle = 0x01;
const int kQrChannelAccessPoint = 0x02;
const int kQrChannelCtDisc = 0x04;

/// Bits 0-2 are assigned; bits 3-7 are reserved and must be zero.
const int kQrChannelKnownMask = 0x07;

const int _kMaxUriBytes = 128;

final RegExp _kMacSuffixPattern = RegExp(r'^[0-9A-F]{6}$');
final RegExp _kModelPattern = RegExp(r'^[A-Z0-9_-]{1,16}$');
final RegExp _kGuideIdPattern = RegExp(r'^[a-z0-9_-]{1,48}$');
final RegExp _kChannelsPattern = RegExp(r'^[0-9A-F]{2}$');

/// A successfully parsed guide QR.
///
/// Field semantics:
/// - [macSuffix]: last 6 hex characters of the device MAC, uppercase.
/// - [model]: MODEL prefix that also leads `device_name` in BLE adverts.
/// - [channelMask]: bitmap of discovery channels the device listens on.
/// - [guideId]: guide identifier; unknown ids fall back to a generic guide.
class DeviceQrUri {
  const DeviceQrUri({
    required this.macSuffix,
    required this.model,
    required this.channelMask,
    required this.guideId,
  });

  /// Parses [raw] QR text; returns `null` on any spec violation.
  ///
  /// Surrounding whitespace is tolerated (decode engines sometimes emit
  /// it) but everything inside must be exact.
  static DeviceQrUri? tryParse(String raw) {
    final uri = raw.trim();
    if (uri.isEmpty) return null;

    // Length cap in bytes; non-ASCII is rejected separately below, so the
    // byte count equals the character count for anything that survives.
    if (uri.length > _kMaxUriBytes) return null;

    // Printable ASCII only: no control chars, no whitespace inside, no '%'
    // (percent-encoding is not part of the grammar and must not be decoded).
    for (final codeUnit in uri.codeUnits) {
      if (codeUnit < 0x21 || codeUnit > 0x7E || codeUnit == 0x25) {
        return null;
      }
    }

    const prefix = 'ctdev://guide-v1/';
    if (!uri.startsWith(prefix)) return null;
    final rest = uri.substring(prefix.length);
    if (rest.isEmpty) return null;

    final queryIndex = rest.indexOf('?');
    if (queryIndex <= 0) return null; // no query or empty path segment
    final path = rest.substring(0, queryIndex);
    final query = rest.substring(queryIndex + 1);

    // One path segment only; fragments never appear ('#' is 0x23, printable,
    // so reject it explicitly in path and query alike).
    if (path.contains('/') || path.contains('#')) return null;
    if (query.contains('#')) return null;
    if (query.contains('?')) return null;
    if (!_kMacSuffixPattern.hasMatch(path)) return null;

    // Exactly the m/c/g keys, each once.
    final values = <String, String>{};
    for (final pair in query.split('&')) {
      final eq = pair.indexOf('=');
      if (eq <= 0 || eq == pair.length - 1) return null; // no '=' or empty value
      final key = pair.substring(0, eq);
      if (key.length != 1 || !'mcg'.contains(key)) return null;
      if (values.containsKey(key)) return null;
      values[key] = pair.substring(eq + 1);
    }
    if (values.length != 3) return null;

    final model = values['m']!;
    final channels = values['c']!;
    final guideId = values['g']!;
    if (!_kModelPattern.hasMatch(model)) return null;
    if (!_kChannelsPattern.hasMatch(channels)) return null;
    if (!_kGuideIdPattern.hasMatch(guideId)) return null;

    final mask = int.parse(channels, radix: 16);
    if (mask & kQrChannelKnownMask == 0) return null; // no known channel
    if (mask & ~kQrChannelKnownMask != 0) return null; // reserved bits set

    return DeviceQrUri(
      macSuffix: path,
      model: model,
      channelMask: mask,
      guideId: guideId,
    );
  }

  final String macSuffix;
  final String model;
  final int channelMask;
  final String guideId;

  bool get hasBle => channelMask & kQrChannelBle != 0;
  bool get hasAccessPoint => channelMask & kQrChannelAccessPoint != 0;
  bool get hasCtDisc => channelMask & kQrChannelCtDisc != 0;

  @override
  String toString() =>
      'ctdev://guide-v1/$macSuffix?m=$model'
      '&c=${channelMask.toRadixString(16).toUpperCase().padLeft(2, '0')}'
      '&g=$guideId';
}
