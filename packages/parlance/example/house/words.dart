/// The house's vocabulary: every state, command, query and fact, written
/// once as an abstract class; parlance_generator makes their typed words,
/// the house's owner base and its client (`words.g.dart`). The rest of the
/// code only ever refers to those.
library;

import 'package:parlance/schema.dart';

part 'words.g.dart';

/// Who acts in the house.
abstract final class Who {
  static const house = Principal('house');
  static const ann = Principal('resident', 'ann');
  static const bob = Principal('guest', 'bob');
  static Principal phone(String name) => Principal('phone', name);
  static Principal agent(String session) => Principal('agent', session);

  /// The module that keeps a visit.
  static const visit = Principal('module', 'visit');

  /// Residents, their phones and agents, and the house itself.
  static const household = Callers({
    'resident': Access.allow,
    'phone': Access.allow,
    'agent': Access.allow,
    'house': Access.allow,
    'system': Access.allow,
  });

  /// [household], and guests with a warning in an editor.
  static const anyone = Callers({
    'resident': Access.allow,
    'phone': Access.allow,
    'agent': Access.allow,
    'house': Access.allow,
    'system': Access.allow,
    'guest': Access.warn,
  });
}

enum Mode { home, away, night }

/// The house's words, in its one vocabulary; its rooms are what it
/// speaks of, keys and refs, for an agent or an editor to choose from.
@Vocabulary('house')
abstract class House {
  /// Whether a room's light is on, by room.
  @StateWord('light', keyOf: 'room')
  bool get light;

  /// The heating's target, °C.
  @StateWord('heat')
  @Range(min: 10, max: 28)
  num get heat;

  @StateWord('mode')
  Mode get mode;

  @StateWord('locked')
  bool get locked;

  /// Anyone may light a room; a guest's call is shown in an editor.
  @CommandWord('set_light', callers: Who.anyone)
  void setLight({@ChoiceOf('room') required String room, required bool on});

  @CommandWord('set_heat')
  void setHeat({@Range(min: 10, max: 28) required num target});

  @CommandWord('set_mode')
  void setMode({required Mode mode});

  /// Locks (on) or unlocks the door; it says why it cannot, before anyone
  /// tries.
  @CommandWord('lock', whyNot: true)
  void lock({required bool on});

  /// The rooms whose light is on ([lit]) or off: a question that changes
  /// nothing.
  @QueryWord('rooms')
  List<String> rooms({required bool lit});

  /// Someone rang the doorbell.
  @FactWord('rang')
  void rang({required String who});

  /// A sensor saw someone in a room.
  @FactWord('motion')
  void motion({required String room});
}

/// A visit's words: who is in, and seeing a guest out. They are there only
/// while a visit is (a scope, `main.dart`).
@Vocabulary('visit')
abstract class Visit {
  @StateWord('guests')
  List<String> get guests;

  @CommandWord('leave')
  void leave({required String who});
}
