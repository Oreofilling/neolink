import 'package:ble_universal/src/security_write_retry.dart';
import 'package:test/test.dart';

void main() {
  test('成功写入不重试', () async {
    var writes = 0;

    await writeWithSecurityRetry(
      write: () async {
        writes++;
      },
      retryOn: (_) => true,
      pauses: const <Duration>[],
    );

    expect(writes, 1);
  });

  test('认证未完成时等待并重试同一次写入', () async {
    var writes = 0;
    final retries = <int>[];

    await writeWithSecurityRetry(
      write: () async {
        writes++;
        if (writes < 3) throw const _SecurityPending();
      },
      retryOn: (error) => error is _SecurityPending,
      pauses: const <Duration>[Duration.zero, Duration.zero],
      onRetry: (error, retry, pause) => retries.add(retry),
    );

    expect(writes, 3);
    expect(retries, <int>[1, 2]);
  });

  test('非认证错误立即原样抛出', () async {
    final failure = StateError('device disconnected');

    await expectLater(
      writeWithSecurityRetry(
        write: () async => throw failure,
        retryOn: (error) => error is _SecurityPending,
        pauses: const <Duration>[Duration.zero],
      ),
      throwsA(same(failure)),
    );
  });

  test('认证等待次数耗尽后抛出最后一次错误', () async {
    var writes = 0;

    await expectLater(
      writeWithSecurityRetry(
        write: () async {
          writes++;
          throw const _SecurityPending();
        },
        retryOn: (error) => error is _SecurityPending,
        pauses: const <Duration>[Duration.zero, Duration.zero],
      ),
      throwsA(isA<_SecurityPending>()),
    );
    expect(writes, 3);
  });
}

final class _SecurityPending implements Exception {
  const _SecurityPending();
}
