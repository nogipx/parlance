/// A house on parlance, start to end: its typed words, who may do what and
/// whether a word is there for them, why a state is as it is and which
/// part did it, a guard, a question that changes nothing, a device changed
/// by hand, modules that say what they need and a visit that comes and
/// goes as a scope, a phone that joins over remote, and the journal of it
/// all: who did what, following what, and who set it going.
///
/// Run: `dart run example/main.dart`.
library;

import 'dart:async';

import 'package:rpc_dart/rpc_dart.dart';
import 'package:parlance/app.dart';
import 'package:parlance/tools.dart' show JournalEntry, JournalFact;

import 'house/house.dart';
import 'house/visit.dart';
import 'house/words.dart';

Future<void> main() async {
  // --- The host and its owner ----------------------------------------------

  final host = Host(onError: (e, st) => print('error: $e'));
  // What tools see of it (the journal, why a state is as it is): its
  // registry, which promises less than the host does.
  final registry = host.registry;
  // Everything done, as it happens, from the start: a host writes it where
  // it lasts (package:parlance_journal), since what the registry itself
  // remembers is bounded.
  final journal = <JournalEntry>[];
  final journaling = registry.journal.listen(journal.add);
  final devices = Devices();
  final house = Home(devices);
  // The house speaks through a participant main makes: who it is, its
  // vocabulary (the name its words are named in, said once, in House), who calls its commands when a command does
  // not say (the household), and that the doorbell says who rang (a fact
  // on a visitor's behalf). The owner's code never says what it may.
  final houseSide = host.participant(
    Who.house,
    vocabularies: [houseWords],
    access: const WordAccess(call: Who.household),
    rights: ParticipantRights(
      speakFor: (_, by, fact) => fact == HouseFact.rang.name
          ? null
          : 'only the doorbell speaks for anyone',
    ),
  );
  // The owner is the participant's part `devices`, named here: what it
  // writes and says is told as house@devices.
  houseSide.attach({'devices': house});

  // Ann and bob act through participants of their own, as every part does:
  // what each may call is what its principal may, and main hands out no
  // registry to act as anyone. Each uses the house through its client.
  final annSide = host.participant(Who.ann);
  final bobSide = host.participant(Who.bob);
  final ann = HouseClient(annSide);
  final bob = HouseClient(bobSide);

  // --- 1. Typed calls, and who may make them --------------------------------

  section('Typed calls');
  // The params are the word's: another command's do not compile.
  await show(
    'ann turns the kitchen light on',
    () => ann.setLight(room: 'kitchen', on: true),
  );
  print('  kitchen light: ${ann.lightOf('kitchen')}');
  // Why it is on: on whose behalf the owner wrote it, the message that set
  // it going, and the call it was answering.
  final why = registry.explain(HouseState.light.name, key: 'kitchen');
  final wrote = why.change!;
  print(
    '  why: written by ${wrote.cause.by}, '
    'started by ${wrote.cause.originOf(wrote.state)}',
  );
  for (final c in why.trail) {
    print('    answering ${c.command} ${c.params} by ${c.cause.by}');
  }
  await show('bob, a guest, sets the heating', () => bob.setHeat(target: 25));
  await show(
    'ann lights a room there is not',
    () => ann.setLight(room: 'attic', on: true),
  );
  // Whether a word is there for someone, before calling it: a part shows
  // a missing or a closed word for what it is.
  print(
    '  for bob: ${HouseCommand.setHeat.name} '
    '${bob.status(HouseCommand.setHeat)}, '
    '${HouseCommand.setLight.name} '
    '${bob.status(HouseCommand.setLight)}, '
    '${VisitState.guests.name} ${VisitClient(bobSide).status(VisitState.guests)}',
  );

  // --- 2. A guard of the house -----------------------------------------------

  section('A guard');
  await ann.setMode(mode: Mode.night);
  final agentSide = host.participant(Who.agent('night'));
  await show(
    'an agent unlocks at night',
    () => HouseClient(agentSide).lock(on: false),
  );
  await show('ann unlocks at night', () => ann.lock(on: false));
  await ann.lock(on: true);
  agentSide.dispose();
  await ann.setMode(mode: Mode.home);

  // --- 3. A query: a question that changes nothing -----------------------------

  section('A query');
  // Asked, not called: it only answers, so asking again is safe, and the
  // registry keeps nothing of it (no call record, no id held).
  print('  rooms lit, asked by bob: ${await bob.rooms(lit: true)}');
  print('  and dark: ${await bob.rooms(lit: false)}');

  // --- 4. A switch flipped by hand ---------------------------------------------

  section('By hand');
  // Nobody called a command: the device changed, and the owner is synced
  // because it said where its changes come from.
  final before = ann.lightOf('kitchen');
  devices.flip('kitchen');
  await annSide.settle();
  print(
    '  the kitchen switch flipped by hand: '
    'from $before to ${ann.lightOf('kitchen')}',
  );

  // --- 5. A module beside the house, as a scope ----------------------------

  section('A visit, as a scope');
  // A visit is made when guests come and goes when they leave: its words
  // are there only meanwhile, and leave nothing behind.
  final visitSide = host.participant(
    Who.visit,
    vocabularies: [visitWords],
    access: const WordAccess(call: Who.household),
  );
  visitSide.attach({'book': GuestBook()});
  await annSide.settle();
  final visit = VisitClient(annSide);
  print('  during the visit: visit.guests ${visit.status(VisitState.guests)}');
  house.ring(Who.bob, 'bob');
  await annSide.settle();
  print('  guests: ${visit.guests}');
  // The guest book wrote it, answering the ring: nobody passed where it
  // started, the registry gives it from the fact the book followed.
  final booked = registry.lastChange(VisitState.guests.name)!.cause;
  print('  written by ${booked.by}, started by ${booked.origin}');
  visitSide.dispose();
  print('  after the visit: visit.guests ${visit.status(VisitState.guests)}');

  // --- 6. A phone that joins over remote ------------------------------------

  section('A phone over remote');
  // The phone is a participant like the house, across a connection: the
  // house opens a session for it and says who it is; it reads what it
  // watches.
  final phone = await Phone.join(host, Who.phone('ann-phone'));
  // It knows the house through the same client: getters and streams for
  // states, methods for commands, no word or record in sight.
  final IHouseClient home = HouseClient(phone.part);
  final heats = home.heatChanges.listen((_) {});
  final modes = home.modeChanges.listen((_) {});
  await home.setHeat(target: 22);
  print('  the phone sets the heating: done');
  // A call answers once the phone's copy has what it wrote.
  print('  the phone sees: ${home.heat} °C, mode ${home.mode?.name}');
  await show('the phone sets 40 °C', () => home.setHeat(target: 40));
  await heats.cancel();
  await modes.cancel();
  await phone.close();

  // --- 7. The journal -------------------------------------------------------

  section('The journal');
  // The ring's conversation, as it happened: what it led to, by whom, and
  // the message that set it going, on every entry.
  final ring = journal.whereType<JournalFact>().firstWhere(
    (e) => e.fact.fact == HouseFact.rang.name,
  );
  for (final e in journal.where((e) => e.conversation == ring.conversation)) {
    print('  ${e.kind} ${e.word} by ${e.cause.by}, started by ${e.origin}');
  }
  final talks = {for (final e in journal) e.conversation};
  print('  in all: ${journal.length} entries, ${talks.length} conversations');
  await journaling.cancel();

  annSide.dispose();
  bobSide.dispose();
  houseSide.dispose();
  await host.dispose();
}

/// A phone's connection: a session the house opens for it, and the phone's
/// side, a participant joined over an [RpcClientConnection].
final class Phone {
  Phone._(this.part, this._connection, this._session, this._host);

  static Future<Phone> join(Host house, Principal principal) async {
    final (c, s) = RpcChannelTransport.memoryPair();
    // The host decides who the connection is, when it accepts it.
    final host = RpcPeerEndpoint(transport: s);
    final session = house.participant(principal).serve(host);
    host.start();
    // In memory the connection does not come back once lost; over a socket
    // the factory would dial again, and the phone would join again.
    final connection = RpcClientConnection(
      transportFactory: (_) async => c,
      shouldReconnect: (_) => false,
    );
    final part = await Host.join(connection);
    return Phone._(part, connection, session, host);
  }

  final IRemoteParticipant part;
  final RpcClientConnection _connection;
  final IRemoteSession _session;
  final RpcPeerEndpoint _host;

  Future<void> close() async {
    await part.close();
    await _connection.dispose();
    _session.close();
    await _host.close();
  }
}

void section(String title) => print('\n$title');

/// What a call came to, in a line: a refusal with its code and guard, any
/// other end in the result's own words.
Future<void> show(String what, Future<void> Function() call) async {
  try {
    await call();
    print('  $what: done');
  } on CallNotDone catch (e) {
    final r = e.result;
    print(
      '  $what: ${switch (r) {
        CallRefused(:final code, :final guard) => 'refused (${code.name}${guard == null ? '' : ' by $guard'}): ${r.whyNot}',
        _ => r.whyNot,
      }}',
    );
  }
}
