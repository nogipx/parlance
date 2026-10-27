part of '_index.dart';

@Vocabulary('light')
abstract class Lights {
  @CommandWord()
  void on({required Room room});
}
