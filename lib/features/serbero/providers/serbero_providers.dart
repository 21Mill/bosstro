import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bosstro/features/nodes/providers/node_providers.dart';
import 'package:bosstro/features/serbero/services/serbero_core.dart';
import 'package:bosstro/features/solver_key/providers/solver_key_providers.dart';

/// The core behind Serbero's reports. Tests override it with a fake.
final serberoCoreProvider = Provider<SerberoCore>(
  (ref) => const RustSerberoCore(),
);

/// The disputes whose Serbero reports changed on the active node.
final serberoUpdatesProvider = StreamProvider<String>(
  (ref) => ref.watch(serberoCoreProvider).updates(),
);

/// What Serbero sent about one dispute, live: read again when a report of
/// it arrives. Null without an active node or a loaded key.
final serberoMediationProvider = AsyncNotifierProvider.autoDispose
    .family<SerberoMediationNotifier, SerberoMediation?, String>(
      SerberoMediationNotifier.new,
    );

class SerberoMediationNotifier
    extends AutoDisposeFamilyAsyncNotifier<SerberoMediation?, String> {
  SerberoCore get _core => ref.read(serberoCoreProvider);

  @override
  Future<SerberoMediation?> build(String arg) async {
    ref.watch(activeNodeProvider);
    ref.watch(solverKeyProvider);
    ref.listen(serberoUpdatesProvider, (_, next) {
      final disputeId = next.valueOrNull;
      if (disputeId == arg || disputeId == '') unawaited(_reload());
    });
    return _core.mediation(arg);
  }

  Future<void> _reload() async {
    try {
      state = AsyncData(await _core.mediation(arg));
    } catch (e) {
      debugPrint('[serbero] not read from storage: $e');
    }
  }
}
