/// CT-Prov over the device softAP HTTP binding (protocol doc section 16).
///
/// The device runs the same dispatcher behind POST /api/v1/ctprov on its
/// softAP gateway address (NE101: 192.168.1.1). Each request is one whole
/// envelope per HTTP round trip — no GATT fragmentation layer, no
/// message_id/fragment_* fields. session.close is acknowledged without a
/// link teardown (section 11 "disconnecting directly is equivalent");
/// there is no connection state to hold, so [close] only releases the
/// HTTP client.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ct_prov_core/ct_prov_core.dart';

/// Failure codes for [SoftapTransportException].
///
/// Stable identifiers: the UI maps them to localized guidance (e.g.
/// ap_unreachable -> "join the device AP first, then retry").
enum SoftapTransportError {
  /// TCP/HTTP layer could not reach the device (not joined to the AP,
  /// device left config mode, wrong gateway address).
  apUnreachable('ap_unreachable'),

  /// Device answered a non-200 status (its 400 path: body is not a
  /// request envelope or exceeds the 4096-byte cap).
  httpStatus('http_status'),

  /// 200 body did not decode as a response envelope (protocol shape).
  badEnvelope('bad_envelope'),

  /// Used after [SoftapCtTransport.close].
  closed('transport_closed');

  const SoftapTransportError(this.wireName);

  /// Stable identifier carried in exceptions and logs.
  final String wireName;
}

/// SoftAP transport failure with a stable [code] for UI mapping.
final class SoftapTransportException implements Exception {
  const SoftapTransportException(this.error, this.detail);

  final SoftapTransportError error;

  /// Human-readable diagnostic; never parsed.
  final String detail;

  /// Stable reason string (matches SoftapTransportError.wireName).
  String get code => error.wireName;

  @override
  String toString() => 'SoftapTransportException($code): $detail';
}

/// Default device softAP endpoint (protocol doc section 16; NE101 gateway).
final Uri kDefaultSoftapEndpoint =
    Uri.parse('http://192.168.1.1/api/v1/ctprov');

/// One-request-per-round-trip CT-Prov transport over device softAP HTTP.
///
/// The [ProvTransport] port makes this interchangeable with the BLE GATT
/// transport inside CtSessionClient (tech selection C-15). The section 16
/// model has no shared connection state: each call is an independent POST
/// and the device dispatcher serializes concurrent requests internally.
final class SoftapCtTransport implements ProvTransport {
  SoftapCtTransport({Uri? endpoint, HttpClient? httpClient})
      : _endpoint = endpoint ?? kDefaultSoftapEndpoint,
        _client = httpClient ?? HttpClient();

  /// Device endpoint: POST target for whole request envelopes.
  final Uri _endpoint;
  final HttpClient _client;

  bool _closed = false;

  @override
  Future<ProvResponse> sendRequest(
    ProvRequest request, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (_closed) {
      throw StateError('transport closed before request sent');
    }
    final body = encodeRequest(
      id: request.id,
      op: request.opName,
      data: request.data,
    );
    final HttpClientResponse response;
    try {
      final httpRequest =
          await _client.openUrl('POST', _endpoint).timeout(timeout);
      httpRequest.headers.contentType = ContentType.json;
      httpRequest.headers.contentLength = utf8.encode(body).length;
      httpRequest.write(body);
      response = await httpRequest.close().timeout(timeout);
    } catch (error) {
      // TimeoutException propagates raw (GATT transport parity): callers
      // treat it as a request timeout, not as an unreachable device.
      if (error is TimeoutException) rethrow;
      throw _mapNetworkError(error);
    }

    if (response.statusCode != 200) {
      // Drain so the keep-alive connection is not left half-read.
      await response.drain<void>().catchError((Object _) {});
      throw SoftapTransportException(
        SoftapTransportError.httpStatus,
        'device answered HTTP ${response.statusCode}',
      );
    }

    final List<int> wire;
    try {
      wire = await response
          .timeout(timeout)
          .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk));
    } catch (error) {
      throw _mapNetworkError(error);
    }
    final ProvEnvelope envelope;
    try {
      envelope = decodeEnvelope(wire);
    } on ProvEnvelopeException catch (error) {
      throw SoftapTransportException(
        SoftapTransportError.badEnvelope,
        'response body is not a CT-Prov envelope (${error.reason})',
      );
    }
    if (envelope is! ProvResponse) {
      throw const SoftapTransportException(
        SoftapTransportError.badEnvelope,
        'response body is not a response envelope',
      );
    }
    // One request per connection: the response id must be the request id
    // (the GATT transport ignores foreign ids per section 6.4 because it
    // multiplexes; over HTTP a mismatch can only be a broken device).
    if (envelope.id != request.id) {
      throw SoftapTransportException(
        SoftapTransportError.badEnvelope,
        'response id ${envelope.id} does not match request id ${request.id}',
      );
    }
    return envelope;
  }

  @override
  Future<void> close() async {
    _closed = true;
    _client.close(force: true);
  }

  /// Network-layer failures collapse to ap_unreachable — the dominant
  /// softAP failure is "not joined to the device AP", and the UI needs one
  /// stable reason to guide the user. Everything else (envelope shape,
  /// HTTP status) keeps its own finer code.
  SoftapTransportException _mapNetworkError(Object error) =>
      SoftapTransportException(SoftapTransportError.apUnreachable, '$error');
}
