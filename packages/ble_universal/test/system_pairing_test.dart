import 'dart:async';

import 'package:ble_universal/src/system_pairing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  /// 构造记录调用的编排器。
  (
    CtSystemPairing,
    List<String> steps,
    List<String> paired,
    List<String> nativeCalls,
    List<String> fallbackCalls,
  )
  makePairing({
    required bool? isPairedResult,
    Object? nativeError,
    bool hasApi = true,
  }) {
    final steps = <String>[];
    final paired = <String>[];
    final nativeCalls = <String>[];
    final fallbackCalls = <String>[];
    final pairing = CtSystemPairing(
      isPaired: (deviceId) async {
        paired.add(deviceId);
        return isPairedResult;
      },
      nativePair: (deviceId, timeout) async {
        nativeCalls.add(deviceId);
        if (nativeError != null) throw nativeError;
        return 'CustomPairAsync/Paired';
      },
      fallbackPair: (deviceId, timeout) async {
        fallbackCalls.add(deviceId);
      },
      hasSystemPairingApi: () => hasApi,
    );
    return (pairing, steps, paired, nativeCalls, fallbackCalls);
  }

  test('已配对：直接复用 bond，不触发任何配对调用', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final (pairing, steps, paired, nativeCalls, fallbackCalls) = makePairing(
      isPairedResult: true,
    );

    await pairing.establish('9C:13:9E:BB:C6:DE', onStep: steps.add);

    expect(paired, hasLength(1));
    expect(nativeCalls, isEmpty);
    expect(fallbackCalls, isEmpty);
    expect(steps.last, 'pre-open: isPaired=true');
  });

  test('Windows 原生通道成功：回报状态且不触碰回退', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final (pairing, steps, _, nativeCalls, fallbackCalls) = makePairing(
      isPairedResult: false,
    );

    await pairing.establish('9C:13:9E:BB:C6:DE', onStep: steps.add);

    expect(nativeCalls, hasLength(1));
    expect(fallbackCalls, isEmpty);
    expect(
      steps.last,
      'pre-open: Windows PairAsync status=CustomPairAsync/Paired',
    );
  });

  test('Windows 原生通道缺失：回退 universal_ble pair', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final (pairing, steps, _, nativeCalls, fallbackCalls) = makePairing(
      isPairedResult: false,
      nativeError: MissingPluginException(),
    );

    await pairing.establish('9C:13:9E:BB:C6:DE', onStep: steps.add);

    expect(nativeCalls, hasLength(1));
    expect(fallbackCalls, hasLength(1));
    expect(steps, contains('pre-open: native channel missing; fallback'));
  });

  test('Windows 原生配对失败：抛出携带状态信息的 CtPairingException', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final (pairing, _, _, _, fallbackCalls) = makePairing(
      isPairedResult: false,
      nativeError: PlatformException(
        code: 'pair-failed',
        message:
            'Windows CustomPairAsync(ConfirmOnly, Encryption) '
            'status: ConnectionRejected',
      ),
    );

    await expectLater(
      pairing.establish('9C:13:9E:BB:C6:DE'),
      throwsA(
        isA<CtPairingException>().having(
          (error) => error.message,
          'message',
          contains('ConnectionRejected'),
        ),
      ),
    );
    expect(fallbackCalls, isEmpty);
  });

  test('Windows 原生配对超时：转为 CtPairingException', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final (pairing, _, _, _, _) = makePairing(
      isPairedResult: false,
      nativeError: TimeoutException('15s'),
    );

    await expectLater(
      pairing.establish('9C:13:9E:BB:C6:DE'),
      throwsA(isA<CtPairingException>()),
    );
  });

  test('无配对 API 的平台：交给设备侧安全请求，不发起配对', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final (pairing, steps, _, nativeCalls, fallbackCalls) = makePairing(
      isPairedResult: false,
      hasApi: false,
    );

    await pairing.establish('9C:13:9E:BB:C6:DE', onStep: steps.add);

    expect(nativeCalls, isEmpty);
    expect(fallbackCalls, isEmpty);
    expect(
      steps.last,
      'pre-open: no system pairing API; relying on device security request',
    );
  });

  test('有配对 API 的非 Windows 平台：走通用 pair', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final (pairing, steps, _, nativeCalls, fallbackCalls) = makePairing(
      isPairedResult: false,
    );

    await pairing.establish('9C:13:9E:BB:C6:DE', onStep: steps.add);

    expect(nativeCalls, isEmpty);
    expect(fallbackCalls, hasLength(1));
    expect(steps, contains('pre-open: system pairing requested'));
  });
}
