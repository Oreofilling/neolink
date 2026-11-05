/// softap_transport tests: an in-process HttpServer plays the section 16
/// device (POST /api/v1/ctprov, whole envelopes, session.close acked
/// without teardown) and the client is exercised through both the happy
/// path and every failure mapping.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ct_prov_core/ct_prov_core.dart';
import 'package:softap_transport/softap_transport.dart';
import 'package:test/test.dart';

/// Minimal section 16 device: decodes request envelopes, answers canned
/// responses, records everything it saw.
class _FakeDevice {
  _FakeDevice(this.server);

  final HttpServer server;
  final List<Map<String, Object?>> requests = [];
  final List<String> rawBodies = [];
  final List<String?> contentTypes = [];

  /// op -> response JSON builder.
  final Map<String, String Function(int id)> responders = {};

  /// When set, the device answers this status instead of 200.
  int? forceStatus;

  /// When set, the device writes this raw body with a 200.
  String? forceRawBody;

  static Future<_FakeDevice> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final device = _FakeDevice(server);
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      device.rawBodies.add(body);
      device.contentTypes.add(request.headers.contentType?.toString());
      Object? decoded;
      try {
        decoded = jsonDecode(body);
      } on FormatException {
        decoded = null;
      }
      device.requests.add(
        decoded is Map
            ? Map<String, Object?>.from(decoded)
            : <String, Object?>{},
      );
      final response = request.response;
      if (device.forceStatus != null) {
        response.statusCode = device.forceStatus!;
        await response.close();
        return;
      }
      if (device.forceRawBody != null) {
        response.headers.contentType = ContentType.json;
        response.write(device.forceRawBody);
        await response.close();
        return;
      }
      final id = decoded is Map ? decoded['id'] : null;
      final op = decoded is Map ? decoded['op'] : null;
      final builder = op is String ? device.responders[op] : null;
      response.headers.contentType = ContentType.json;
      if (id is! int || builder == null) {
        response.statusCode = 400;
        await response.close();
        return;
      }
      response.write(builder(id));
      await response.close();
    });
    return device;
  }

  Uri get endpoint =>
      Uri.parse('http://127.0.0.1:${server.port}/api/v1/ctprov');

  Future<void> stop() => server.close();
}

ProvRequest _req(int id, String op) =>
    ProvRequest(id: id, opName: op, data: const {});

void main() {
  test('wire format is one whole envelope per POST', () async {
    final device = await _FakeDevice.start();
    final transport = SoftapCtTransport(endpoint: device.endpoint);
    device.responders['device.info.get'] = (id) =>
        '{"id":$id,"op":"device.info.get.result","ok":true,"data":{"device_name":"NE101-BBC6DC"}}';
    final response = await transport.sendRequest(_req(7, 'device.info.get'));

    expect(response.id, 7);
    expect(response.opName, 'device.info.get.result');
    expect(response.ok, isTrue);
    expect(response.data?['device_name'], 'NE101-BBC6DC');
    // Golden body: compact envelope, key order id/op/data (section 6.1).
    expect(
      device.rawBodies.single,
      '{"id":7,"op":"device.info.get","data":{}}',
    );
    expect(device.contentTypes.single, contains('application/json'));
    await transport.close();
    await device.stop();
  });

  test('session.close is acked without any teardown side effect', () async {
    final device = await _FakeDevice.start();
    final transport = SoftapCtTransport(endpoint: device.endpoint);
    device.responders['session.close'] =
        (id) => '{"id":$id,"op":"session.close.result","ok":true,"data":{}}';
    final response = await transport.sendRequest(_req(1, 'session.close'));

    expect(response.ok, isTrue);
    expect(response.opName, 'session.close.result');
    // Section 16: the ack carries no link teardown; the device stays up.
    expect(device.requests.single['op'], 'session.close');
    await transport.close();
    await device.stop();
  });

  test('error envelopes pass through with code and message intact', () async {
    final device = await _FakeDevice.start();
    final transport = SoftapCtTransport(endpoint: device.endpoint);
    device.responders['config.set'] =
        (id) => '{"id":$id,"op":"config.set.result","ok":false,'
            '"error":{"code":"FIELD_NOT_SUPPORTED","message":"mqtt: secret"}}';
    final response = await transport.sendRequest(
      ProvRequest(id: 2, opName: 'config.set', data: const {
        'mqtt': {'secret': 'x'},
      }),
    );

    expect(response.ok, isFalse);
    expect(response.error?.codeName, 'FIELD_NOT_SUPPORTED');
    expect(response.error?.code, ProvErrorCode.fieldNotSupported);
    await transport.close();
    await device.stop();
  });

  test('HTTP non-200 maps to httpStatus (device 400 path)', () async {
    final device = await _FakeDevice.start();
    final transport = SoftapCtTransport(endpoint: device.endpoint);
    device.forceStatus = 400;

    await expectLater(
      transport.sendRequest(_req(1, 'device.info.get')),
      throwsA(
        isA<SoftapTransportException>()
            .having((e) => e.code, 'code', 'http_status'),
      ),
    );
    await transport.close();
    await device.stop();
  });

  test('a 200 body that is not a response envelope maps to badEnvelope',
      () async {
    final device = await _FakeDevice.start();
    final transport = SoftapCtTransport(endpoint: device.endpoint);
    device.forceRawBody = 'not json at all';

    await expectLater(
      transport.sendRequest(_req(1, 'device.info.get')),
      throwsA(
        isA<SoftapTransportException>()
            .having((e) => e.code, 'code', 'bad_envelope'),
      ),
    );
    await transport.close();
    await device.stop();
  });

  test('a response id mismatching the request maps to badEnvelope', () async {
    final device = await _FakeDevice.start();
    final transport = SoftapCtTransport(endpoint: device.endpoint);
    device.responders['device.info.get'] = (id) =>
        '{"id":${id + 1},"op":"device.info.get.result","ok":true,"data":{}}';

    await expectLater(
      transport.sendRequest(_req(5, 'device.info.get')),
      throwsA(
        isA<SoftapTransportException>()
            .having((e) => e.code, 'code', 'bad_envelope'),
      ),
    );
    await transport.close();
    await device.stop();
  });

  test('connection refused maps to ap_unreachable', () async {
    // Bind then close to find a free port nothing listens on.
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final deadPort = probe.port;
    await probe.close();
    final transport = SoftapCtTransport(
      endpoint: Uri.parse('http://127.0.0.1:$deadPort/api/v1/ctprov'),
    );

    await expectLater(
      transport.sendRequest(_req(1, 'device.info.get')),
      throwsA(
        isA<SoftapTransportException>()
            .having((e) => e.code, 'code', 'ap_unreachable'),
      ),
    );
    await transport.close();
  });

  test('a device slower than the timeout surfaces TimeoutException', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final transport = SoftapCtTransport(
      endpoint: Uri.parse('http://127.0.0.1:${server.port}/api/v1/ctprov'),
    );
    // Accept the request but answer only after the client has given up.
    unawaited(
      server.first.then((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        await request.response.close();
      }),
    );

    await expectLater(
      transport.sendRequest(
        _req(1, 'device.info.get'),
        timeout: const Duration(milliseconds: 150),
      ),
      throwsA(isA<TimeoutException>()),
    );
    await transport.close();
    await server.close();
  });

  test('sendRequest after close throws StateError', () async {
    final transport = SoftapCtTransport(
      endpoint: Uri.parse('http://127.0.0.1:1/api/v1/ctprov'),
    );
    await transport.close();

    expect(
      () => transport.sendRequest(_req(1, 'device.info.get')),
      throwsStateError,
    );
  });

  test('default endpoint is the device softAP gateway', () {
    expect(
      kDefaultSoftapEndpoint.toString(),
      'http://192.168.1.1/api/v1/ctprov',
    );
  });
}
