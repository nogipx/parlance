import 'package:parlance/app.dart';
import 'package:parlance/tools.dart' show RawAccess;
import 'package:test/test.dart';

import 'fixtures/clock.dart';

final class Bedside extends ClockOwnerBase {
  @override
  void setAlarm({required DateTime at}) => alarm.set(at);
}

void main() {
  test('a moment is a DateTime in Dart and milliseconds in JSON', () async {
    final host = Host();
    host.participant(const Principal('clock'), owners: [Bedside()]);
    final me = host.participant(const Principal('user', 'ann'));
    final clock = IClockClient(me);
    final at = DateTime.utc(2026, 10, 30, 7);
    await clock.setAlarm(at: at);
    await me.settle();
    expect(clock.alarm.value, at);
    expect(me.raw.read('clock.alarm'), at.millisecondsSinceEpoch);
    expect(host.registry.stateDescriptor('clock.alarm')!.type.toJson(), {
      'type': 'datetime',
    });
    await host.dispose();
  });
}
