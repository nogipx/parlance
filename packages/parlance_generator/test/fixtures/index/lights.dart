part of '_index.dart';

@Vocabulary('light')
abstract class Lights {
  @CommandWord('on')
  void on({required Room room});
}
