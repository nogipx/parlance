/// A module beside the house: a visit, made when guests come and gone
/// when they leave.
library;

import 'package:parlance/schema.dart';

import 'words.dart';

/// Keeps who is visiting: it hears the doorbell and sees guests out. It
/// knows the house only by its words. Its own words come from its base,
/// made from [Visit]; what it sets in answer to the ring follows from it.
final class GuestBook extends VisitOwner {
  GuestBook() {
    guests = const [];
    whenAttached(
      (p) => hear(
        HouseClient(p).rangFacts,
        (rang) => guests = [...?guests, rang.who],
      ),
    );
  }

  @override
  void leave({required String who}) =>
      guests = [...?guests?.where((g) => g != who)];
}
