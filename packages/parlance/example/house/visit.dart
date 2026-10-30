/// A module beside the house: a visit, made when guests come and gone
/// when they leave.
library;

import 'package:parlance/schema.dart';

import 'words.dart';

/// Keeps who is visiting: it hears the doorbell and sees guests out. It
/// knows the house only by its words. Its own words come from its base,
/// made from [Visit]; what it sets in answer to the ring follows from it.
final class GuestBook extends VisitOwnerBase {
  GuestBook() {
    guests.set(const []);
    hear(
      fact: IHouseClient.of(this).rang,
      onData: (rang) => guests.set([...?guests.value, rang.who]),
    );
  }

  @override
  void leave({required String who}) =>
      guests.set([...?guests.value?.where((g) => g != who)]);
}
