part of '_index.dart';

@Vocabulary('door')
abstract class Doors {
  @StateWord(key: 'door')
  Room get room;
}
