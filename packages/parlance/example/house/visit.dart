/// A module beside the house: a visit, made when guests come and gone
/// when they leave.
library;

import 'package:parlance/schema.dart';

import 'words.dart';

/// Keeps who is visiting: it hears the doorbell and sees guests out. It
/// knows the house only by its words. Its own words and their writers
/// come from its base, made from [Visit].
final class GuestBook extends VisitOwner {
  final List<String> _in = [];

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
