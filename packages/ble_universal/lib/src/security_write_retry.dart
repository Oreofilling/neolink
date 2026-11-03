/// Executes an encrypted GATT write, allowing a peripheral-initiated SMP
/// handshake to finish after the first protected write is rejected.
Future<void> writeWithSecurityRetry({
  required Future<void> Function() write,
  required bool Function(Object error) retryOn,
  List<Duration> pauses = const <Duration>[
    Duration(milliseconds: 250),
    Duration(milliseconds: 500),
    Duration(milliseconds: 750),
    Duration(seconds: 1),
    Duration(seconds: 1),
    Duration(seconds: 1),
  ],
  void Function(Object error, int retry, Duration pause)? onRetry,
}) async {
  var retry = 0;
  while (true) {
    try {
      await write();
      return;
    } catch (error) {
      if (!retryOn(error) || retry >= pauses.length) rethrow;
      final pause = pauses[retry];
      retry++;
      onRetry?.call(error, retry, pause);
      await Future<void>.delayed(pause);
    }
  }
}
