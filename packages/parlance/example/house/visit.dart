/// Two modules beside the house: a visit, made when guests come and gone
/// when they leave, and a garden that cannot start without the weather.
library;

import 'package:parlance/owners.dart';
import 'package:parlance/participant.dart';
import 'package:parlance/registry.dart';

import 'words.dart';

/// Keeps who is visiting: it hears the doorbell and sees guests out. It
/// knows the house only by its words, and says which it needs.
final class Visit extends Owner {
  final List<String> _guests = [];
  late final StateWriterOf<List<String>> _list;

  @override
  Iterable<IWord> get words => [...VisitState.values, ...VisitCommand.values];

  @override
  Iterable<Use> get uses => const [
    Use.required(HouseFact.rang),
    Use.optional(HouseState.mode),
  ];

  @override
  void define(IParticipant p) {
    _list = keep(p.state(VisitState.guests).define());
    keep(
      p.command(VisitCommand.leave).define((c) {
        _guests.remove(c.params.who);
        _list.set([..._guests], cause: c.causeFor(p.who));
      }),
    );
    listen(p.fact(HouseFact.rang).stream, (f) {
      _guests.add(f.payload.who);
      _list.set([..._guests], cause: Cause(p.who, parent: f.message.id));
    });
  }

  @override
  void sync() => _list.set([..._guests]);
}

/// Waters the garden unless it rains: without a weather station it cannot
/// work, and says so.
final class Sprinkler extends Owner {
  @override
  Iterable<Use> get uses => const [Use.required(WeatherState.rain)];

  @override
  void define(IParticipant p) {}
}
