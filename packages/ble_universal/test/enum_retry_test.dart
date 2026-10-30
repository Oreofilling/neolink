import 'dart:async';

import 'package:ble_universal/src/enum_retry.dart';
import 'package:test/test.dart';

void main() {
  test('returns first-attempt value without retrying', () async {
    // Arrange
    var calls = 0;

    // Act
    final result = await runWithEnumRetry(
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

  test('retries after StateError and succeeds on a later attempt', () async {
    // Arrange
    var calls = 0;

    // Act
    final result = await runWithEnumRetry<int>(
      () async {
        calls++;
        if (calls < 3) {
          throw StateError('CT-Prov characteristics missing');
        }
        return calls;
      },
      pause: Duration.zero,
    );

    // Assert
    expect(result, 3);
    expect(calls, 3);
  });

  test('propagates non-StateError immediately without retry', () async {
    // Arrange
    var calls = 0;

    // Act / Assert
    await expectLater(
      runWithEnumRetry(
        () async {
          calls++;
          throw TimeoutException('device slept mid-open');
        },
        pause: Duration.zero,
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(calls, 1);
  });

  test('rethrows last StateError after exhausting attempts', () async {
    // Arrange
    var calls = 0;

    // Act / Assert
    await expectLater(
      runWithEnumRetry(
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
      runWithEnumRetry(
        () async => 'unused',
        maxAttempts: 0,
      ),
      throwsA(isA<ArgumentError>()),
    );
  });
}
