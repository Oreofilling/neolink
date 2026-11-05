/// Transport-agnostic session port: BLE GATT (CtProvGattTransport in
/// ble_adapter) and the device softAP HTTP binding (softap_transport
/// package, protocol doc section 16) implement the same session semantics
/// through this interface (tech selection C-15: same semantics, different
/// wire transports).
library;

import 'envelope.dart';

/// A request/response channel for one CT-Prov session.
///
/// Implementations own the wire details (GATT fragmentation, HTTP request
/// bodies). Envelope encoding and request-id allocation stay with the
/// callers; [sendRequest] must not resolve with a response envelope whose
/// id does not match the request (transports that multiplex, like GATT,
/// associate internally and ignore foreign ids per section 6.4).
abstract interface class ProvTransport {
  /// Sends [request] and resolves with the matching response envelope.
  /// [timeout] bounds the whole round trip; implementations must fail the
  /// future rather than hang past it.
  Future<ProvResponse> sendRequest(ProvRequest request, {Duration timeout});

  /// Releases transport resources. Safe to call repeatedly.
  Future<void> close();
}
