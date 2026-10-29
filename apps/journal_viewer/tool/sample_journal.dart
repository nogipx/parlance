/// Writes a sample journal to look at: a house, guests ringing its bell,
/// a module that answers them, a press on the panel, some of it refused
/// or failed, with real time between.
///
/// Run: `fvm dart run tool/sample_journal.dart [file]` (journal-sample.jsonl).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:parlance/tools.dart';

Future<void> main(List<String> args) async {
  final out = File(args.isEmpty ? 'journal-sample.jsonl' : args.first);
  final sink = out.openWrite();
  final r = Registry();
  final sub = r.journal.listen((e) => sink.writeln(jsonEncode(e.toJson())));
  final rnd = Random(7);
  Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

  const house = Principal('house');
  final p = r.participant(house, vocabularies: [const WordSet.open('house')]);
  final rang = p.defineFact(
    FactDescriptor(
      'house.doorbell.rang',
      type: const ObjectType({'who': Field(TextType())}),
    ),
  );
  final porch = p.defineState(
    StateDescriptor('house.porch.light', type: const BoolType()),
  );
  final locked = p.defineState(
    StateDescriptor('house.door.locked', type: const BoolType()),
  );
  p.defineCommand(
    CommandDescriptor(
      'house.doorbell.ring',
      params: const ObjectType({'who': Field(TextType())}),
      callers: Callers.only(['guest']),
    ),
    (c) => rang.emit({'who': c.params['who']}, cause: c.causeFor(house)),
  );
  var n = 0;
  var lock = true;
  p.defineCommand(
    CommandDescriptor(
      'house.porch.light.set',
      params: const ObjectType({'on': Field(BoolType())}),
      callers: Callers.only(['module', 'resident']),
    ),
    (c) async {
      await wait(120 + rnd.nextInt(400));
      if (++n % 4 == 0) throw StateError('the porch lamp does not answer');
      porch.set(c.params['on'], cause: c.causeFor(house));
      return null;
    },
  );
  p.defineCommand(
    CommandDescriptor(
      'house.door.lock.toggle',
      callers: Callers.only(['resident', 'module']),
    ),
    (c) async {
      await wait(30);
      lock = !lock;
      locked.set(lock, cause: c.causeFor(house));
    },
  );
  p.defineCommand(
    CommandDescriptor('house.alarm.arm', callers: Callers.only(['resident'])),
    (_) {},
  );

  // A module that answers the bell: the porch light, and the alarm when
  // someone says they are leaving (refused: only a resident arms it).
  const visit = Principal('module', 'visit');
  final module = r.participant(visit);
  module.facts('house.doorbell.rang').listen((f) async {
    final who = '${(f.payload as Map)['who']}';
    final cause = Cause(visit, parent: f.id);
    await module.call('house.porch.light.set', {'on': true}, cause: cause);
    if (who.contains('leaving')) {
      await module.call('house.alarm.arm', {}, cause: cause);
    }
  });

  final guests = ['bob', 'carol', 'dan', 'erin'];
  final resident = r.participant(const Principal('resident', 'ann'));
  for (var i = 0; i < 14; i++) {
    final who = r.participant(Principal('guest', guests[i % guests.length]));
    final name = switch (i % 5) {
      4 => '${guests[i % guests.length]}, leaving',
      _ => guests[i % guests.length],
    };
    await who.call('house.doorbell.ring', {'who': name}, id: 'bell:$i');
    if (i % 6 == 2) {
      await resident.call('house.door.lock.toggle', {}, id: 'panel:$i');
    }
    await wait(300 + rnd.nextInt(1500));
  }
  await wait(800);
  await sub.cancel();
  await r.dispose();
  await sink.close();
  stdout.writeln('wrote ${out.path}');
}
