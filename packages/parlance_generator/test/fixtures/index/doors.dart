part of '_index.dart';

@Vocabulary('door', kinds: ['door'])
abstract class Doors {
  @StateWord(key: 'door')
  Room get room;
}
