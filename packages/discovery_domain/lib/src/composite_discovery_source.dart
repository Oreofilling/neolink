/// Fan-in of several discovery sources behind the single
/// [DiscoverySource] seam: the controller keeps one source while the app
/// runs BLE, device-AP and CT-Disc in parallel (M5 task 4: all three
/// channels feed one registry; sources never touch each other).
library;

import 'dart:async';

import '../discovery_domain.dart';

/// Merges the candidate streams of [sources]; start/stop propagate to
/// every child. A child stream error is contained: the composite keeps
/// forwarding the healthy channels (each source already guards its own
/// scan loops; this is the second belt).
final class CompositeDiscoverySource implements DiscoverySource {
  CompositeDiscoverySource(this.sources);

  final List<DiscoverySource> sources;

  final _merged = StreamController<DiscoveryCandidate>.broadcast();
  final List<StreamSubscription<DiscoveryCandidate>> _subs = [];
  bool _started = false;

  @override
  Stream<DiscoveryCandidate> get candidates => _merged.stream;

  @override
  Future<void> start() async {
    if (_started) return;
    _started = true;
    for (final source in sources) {
      _subs.add(
        source.candidates.listen(
          _merged.add,
          onError: (Object _) {},
          cancelOnError: false,
        ),
      );
    }
    // Sequential is deliberate: BLE first (the fast path users watch),
    // then the slower pollers. None of the start()s block on scan results.
    for (final source in sources) {
      await source.start();
    }
  }

  @override
  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    for (final source in sources) {
      await source.stop();
    }
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
  }
}
