import '../link_words.dart';
import '../registry/cause.dart';
import '../registry/messages.dart';
import '../registry/registry.dart';
import '../registry/words.dart';
import 'model.dart';

/// A reaction someone can press, as a control: a button on a desk, a
/// phone, a deck (SPEC §13.12). [Links.controls] gives the ones there are
/// now.
final class LinkControl {
  const LinkControl({
    required this.link,
    required this.look,
    this.lit,
    this.unavailable,
  });

  /// The reaction; its id is what a press presses.
  final Reaction link;

  String get id => link.id;
  String? get name => link.name;

  /// How the host draws it: its manual trigger's options (a label, an
  /// icon...), the host's own words.
  final Map<String, Object?> look;

  /// On or off, for a control that sets something: the condition in
  /// `look['lit']`, else the state its one flip step flips, else whether the
  /// state its one call sets already holds the call's value. Null for a
  /// control that only does something.
  final bool? lit;

  /// Why pressing it cannot work now: the first command it would call is
  /// unavailable. Null when it can.
  final String? unavailable;

  @override
  String toString() =>
      'LinkControl($id${lit == null
          ? ''
          : lit!
          ? ' lit'
          : ' unlit'}'
      '${unavailable == null ? '' : ' unavailable: $unavailable'})';
}

/// What a press came to, in words.
extension PressAnswer on CallResult<LinkOutcome> {
  /// Null when the run went through; else why not: the press was refused,
  /// the link did not run (and why), or the run failed.
  String? get whyNotPressed => switch (this) {
    CallDone(:final value) when value.ran != true =>
      value.reason ?? 'not pressed',
    CallDone(:final value) => value.failure,
    _ => whyNot,
  };
}

extension LinkPresses on Registry {
  /// Presses link [id] on behalf of [by] and waits for its run to end:
  /// null when it went through, else why not ([PressAnswer]).
  Future<String?> pressLink(String id, {required Principal by}) async =>
      (await command(
        LinkWords.press,
      ).call((link: id, args: null, wait: true), by: by)).whyNotPressed;
}
