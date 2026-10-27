/// Two modules beside the house: a visit, made when guests come and gone
/// when they leave, and a garden that cannot start without the weather.
library;

import 'package:parlance/schema.dart';

import 'words.dart';

/// Keeps who is visiting: it hears the doorbell and sees guests out. It
/// knows the house only by its words, and says which it needs. Its own
/// words and their writers come from its base, made from [Visit].
final class GuestBook extends VisitOwner {
  final List<String> _in = [];

  @override
  Iterable<Use> get uses => const [
    Use.required(HouseFact.rang),
    Use.optional(HouseState.mode),
  ];

  @override
  void defineMore(IParticipant p) {
    // It hears the house through the house's client: the fact with its
    // message, so what it writes follows from the ring.
    listen(HouseClient(p).rang, (f) {
      _in.add(f.payload.who);
      guests.set([..._in], cause: Cause(p.who, parent: f.message.id));
    });
  }

  @override
  void leave(CommandCallOf<VisitLeave> call) {
    _in.remove(call.params.who);
    guests.set([..._in], cause: call.inReply);
  }

  @override
  void sync() => guests.set([..._in]);
}

/// Waters the garden unless it rains: without a weather station it cannot
/// work, and says so.
final class Sprinkler extends Owner {
  @override
  Iterable<Use> get uses => const [Use.required(WeatherState.rain)];

  @override
  void define(IParticipant p) {}
}
