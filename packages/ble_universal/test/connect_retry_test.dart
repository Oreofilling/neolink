import 'dart:async';

import 'package:ble_universal/src/connect_retry.dart';
import 'package:test/test.dart';

void main() {
  test('returns first-attempt value without retrying', () async {
    // Arrange
    var calls = 0;

    // Act
    final result = await runWithConnectRetry(
      () async {
        calls++;
        return 'ok';
      },
      pause: Duration.zero,
    );

    // Assert
    expect(result, 'ok');
    expect(calls, 1);
  });

  test('retries on any error type by default and succeeds later', () async {
    // Arrange
    var calls = 0;

    // Act
    final result = await runWithConnectRetry<int>(
      () async {
        calls++;
        if (calls < 3) {
          throw TimeoutException('gatt operation stalled');
        }
        return calls;
      },
      pause: Duration.zero,
    );

    // Assert
    expect(result, 3);
    expect(calls, 3);
  });

  test('propagates immediately when predicate rejects the error', () async {
    // Arrange
    var calls = 0;

    // Act / Assert
    await expectLater(
      runWithConnectRetry(
        () async {
          calls++;
          throw TimeoutException('stalled');
        },
        pause: Duration.zero,
        retryOn: (error) => error is StateError,
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(calls, 1);
  });

  test('rethrows last error after exhausting attempts', () async {
    // Arrange
    var calls = 0;

    // Act / Assert
    await expectLater(
      runWithConnectRetry(
        () async {
          calls++;
          throw StateError('CT-Prov service not found after discovery');
        },
        maxAttempts: 3,
        pause: Duration.zero,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'CT-Prov service not found after discovery',
        ),
      ),
    );
    expect(calls, 3);
  });

  test('rejects maxAttempts below one', () async {
    // Act / Assert
    await expectLater(
      runWithConnectRetry(
        () async => 'unused',
        maxAttempts: 0,
      ),
      throwsA(isA<ArgumentError>()),
    );
  });
}
