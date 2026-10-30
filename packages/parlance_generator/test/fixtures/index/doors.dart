part of '_index.dart';

@Vocabulary('door')
abstract class Doors {
  @StateWord(keyOf: 'door')
  Room get room;
}
