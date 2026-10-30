import 'package:parlance/schema.dart';

part 'clock.g.dart';

/// A clock's words: a moment kept as a Dart DateTime.
@Vocabulary('clock')
abstract class Clock {
  @StateWord('alarm')
  DateTime get alarm;

  @CommandWord('set_alarm', callers: Callers.anyone)
  void setAlarm({required DateTime at});
}
