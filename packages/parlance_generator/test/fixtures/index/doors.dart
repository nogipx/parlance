part of '_index.dart';

@Vocabulary('door')
abstract class Doors {
  @StateWord('room', keyOf: 'door')
  Room get room;
}
