import 'dart:async';

import 'package:bosstro/features/serbero/services/serbero_core.dart';

/// Serbero's reports in Dart: what the test stores per dispute, and a
/// stream the test pushes updates into.
class FakeSerberoCore implements SerberoCore {
  /// Null: no active node or key, so nothing is this key's.
  bool active = true;

  /// The stored mediations, by dispute id (absent: Serbero sent nothing).
  final Map<String, SerberoMediation> mediations = {};

  final _updates = StreamController<String>.broadcast();

  /// Announce that [disputeId]'s reports changed.
  void push(String disputeId) => _updates.add(disputeId);

  @override
  Future<SerberoMediation?> mediation(String disputeId) async {
    if (!active) return null;
    return mediations[disputeId] ?? blankMediation(disputeId);
  }

  @override
  Stream<String> updates() => _updates.stream;
}

SerberoMediation blankMediation(String disputeId) => SerberoMediation(
  disputeId: disputeId,
  transcript: const [],
  transcriptParts: 0,
  transcriptTotal: 0,
  updates: const [],
);

SerberoLine serberoLine(
  SerberoSpeaker? speaker,
  String text, {
  String time = '14:10',
}) => SerberoLine(
  time: speaker == null ? '' : time,
  speaker: speaker,
  text: text,
);
