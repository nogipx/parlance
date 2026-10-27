/// A house on parlance, start to end: its typed words, who may do what and
/// whether a word is there for them, why a state is as it is and which
/// part did it, a guard, a question that changes nothing, a device changed
/// by hand, modules that say what they need and a visit that comes and
/// goes as a scope, a phone that joins over remote and an agent over MCP.
///
/// Run: `dart run example/main.dart`.
library;

import 'dart:async';

import 'package:rpc_dart/rpc_dart.dart';
import 'package:parlance/mcp.dart';
import 'package:parlance/participant.dart';
import 'package:parlance/registry.dart';
import 'package:parlance/remote.dart';
import 'package:parlance/view.dart';

import 'house/house.dart';
import 'house/visit.dart';
import 'house/words.dart';

Future<void> main() async {
  // --- The registry and its owner -------------------------------------------

  final registry = Registry(
    overriders: Who.overriders,
    onError: (e, st) => print('error: $e'),
  );
  final devices = Devices();
  final house = Home(devices);
  // The house speaks through a participant main makes: who it is, its
  // vocabulary (the namespace its words are in, said once, in House), who calls its commands when a command does
  // not say (the household), and that the doorbell says who rang (a fact
  // on a visitor's behalf). The owner's code never says what it may.
  final houseSide = registry.participant(
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
  // writes and says is told as house/devices.
  houseSide.attach({'devices': house});

  final setLight = registry.command(HouseCommand.setLight);
  final setHeat = registry.command(HouseCommand.setHeat);
  final setMode = registry.command(HouseCommand.setMode);
  final lock = registry.command(HouseCommand.lock);
  final light = registry.state(HouseState.light);

  // --- 1. Typed calls, and who may make them --------------------------------

  section('Typed calls');
  // The params are the word's record: another command's do not compile.
  show(
    'ann turns the kitchen light on',
    await setLight.call((room: 'kitchen', on: true), by: Who.ann),
  );
  print('  kitchen light: ${light.read(key: 'kitchen')}');
  // Why it is on: on whose behalf the owner wrote it, and the call it was
  // answering.
  final why = registry.explain(HouseState.light.name, key: 'kitchen');
  print('  why: written by ${why.change?.cause.by}');
  for (final c in why.trail) {
    print('    answering ${c.command} ${c.params} by ${c.cause.by}');
  }
  show(
    'bob, a guest, sets the heating',
    await setHeat.call((target: 25), by: Who.bob),
  );
  show(
    'ann lights a room there is not',
    await setLight.call((room: 'attic', on: true), by: Who.ann),
  );
  // Whether a word is there for someone, before calling it: a part shows
  // a missing or a closed word for what it is.
  final asBob = LocalView(registry, by: Who.bob);
  print(
    '  for bob: ${HouseCommand.setHeat.name} '
    '${asBob.status(HouseCommand.setHeat.name)}, '
    '${HouseCommand.setLight.name} '
    '${asBob.status(HouseCommand.setLight.name)}, '
    'garage.open ${asBob.status('garage.open')}',
  );

  // --- 2. A guard of the house, and overriding it ---------------------------

  section('A guard');
  await setMode.call((mode: Mode.night), by: Who.ann);
  show('ann unlocks at night', await lock.call((on: false), by: Who.ann));
  show(
    'ann unlocks at night, overriding',
    await lock.call((on: false), by: Who.ann, override: true),
  );
  await lock.call((on: true), by: Who.ann);
  await setMode.call((mode: Mode.home), by: Who.ann);

  // --- 3. A query: a question that changes nothing -----------------------------

  section('A query');
  // Asked, not called: it only answers, so asking again is safe, and the
  // registry keeps nothing of it (no call record, no id held).
  final rooms = registry.query(HouseQuery.rooms);
  final lit = await rooms.ask((lit: true), by: Who.bob);
  print('  rooms lit, asked by bob: ${(lit as CallDone<List<String>>).value}');
  final dark = await rooms.ask((lit: false), by: Who.bob);
  print('  and dark: ${(dark as CallDone<List<String>>).value}');

  // --- 4. A switch flipped by hand ---------------------------------------------

  section('By hand');
  // Nobody called a command: the device changed, and the owner is synced
  // because it said where its changes come from.
  final before = light.read(key: 'kitchen');
  devices.flip('kitchen');
  await settle();
  print(
    '  the kitchen switch flipped by hand: '
    'from $before to ${light.read(key: 'kitchen')}',
  );

  // --- 5. A module beside the house, as a scope ----------------------------

  section('A visit, as a scope');
  // A visit is made when guests come and goes when they leave: its words
  // are there only meanwhile, and leave nothing behind.
  final visitSide = registry.participant(
    Who.visit,
    vocabularies: [visitWords],
    access: const WordAccess(call: Who.household),
  );
  visitSide.attach({'book': GuestBook()});
  await settle();
  print(
    '  during the visit: visit.guests ${asBob.status(VisitState.guests.name)}',
  );
  house.ring(Who.bob, 'bob');
  await settle();
  final guests = registry.state(VisitState.guests);
  print('  guests: ${guests.read()}');
  visitSide.dispose();
  print(
    '  after the visit: visit.guests ${asBob.status(VisitState.guests.name)}',
  );

  // --- 6. A phone that joins over remote ------------------------------------

  section('A phone over remote');
  // The phone is a participant like the house, across a connection: the
  // house opens a session for it and says who it is; it reads what it
  // watches.
  final phone = await Phone.join(registry, Who.phone('ann-phone'));
  // It knows the house through the client made from House: getters and
  // streams for states, methods for commands, no word or record in sight.
  final home = HouseClient(phone.part);
  final heats = home.heatChanges.listen((_) {});
  final modes = home.modeChanges.listen((_) {});
  await home.setHeat(target: 22);
  print('  the phone sets the heating: done');
  // A call answers once the phone's copy has what it wrote.
  print('  the phone sees: ${home.heat} °C, mode ${home.mode?.name}');
  try {
    await home.setHeat(target: 40);
  } on CallNotDone catch (e) {
    print('  the phone sets 40 °C: ${e.result.whyNot}');
  }
  final rings = await phone.part.fact(HouseFact.rang).recent(5);
  print('  rings it can see: ${[for (final f in rings) f.payload.who]}');
  await heats.cancel();
  await modes.cancel();
  await phone.close();

  // --- 7. An agent over MCP -------------------------------------------------

  section('An agent over MCP');
  final tools = await parlanceTools(
    LocalBoard(registry, by: Who.agent('demo')),
    commandTools: true,
  );
  print('  its tools: ${[for (final t in tools) t.name].join(', ')}');
  final call = tools.firstWhere((t) => t.name == 'call');
  final answer = await call.run({
    'command': HouseCommand.setLight.name,
    'params': HouseCommand.setLight.params.toJson((room: 'hall', on: false)),
  });
  print('  the agent turns the hall light off: ${answer.text.trim()}');

  houseSide.dispose();
  await registry.dispose();
}

/// A phone's connection: a session the house opens for it, and the phone's
/// side, a participant joined over an [RpcClientConnection].
final class Phone {
  Phone._(this.part, this._connection, this._session, this._host);

  static Future<Phone> join(Registry registry, Principal principal) async {
    final (c, s) = RpcChannelTransport.memoryPair();
    // The host decides who the connection is, when it accepts it.
    final host = RpcPeerEndpoint(transport: s);
    final session = RegistryResponder(host, registry, principal: principal);
    host
      ..registerServiceContract(session)
      ..start();
    // In memory the connection does not come back once lost; over a socket
    // the factory would dial again, and the phone would join again.
    final connection = RpcClientConnection(
      transportFactory: (_) async => c,
      shouldReconnect: (_) => false,
    );
    final part = await RemoteParticipant.join(connection);
    return Phone._(part, connection, session, host);
  }

  final RemoteParticipant part;
  final RpcClientConnection _connection;
  final RegistryResponder _session;
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
void show(String what, CallResult<Object?> r) => print(
  '  $what: ${switch (r) {
    CallDone() => 'done',
    CallRefused(:final code, :final guard, :final overridable) => 'refused (${code.name}${guard == null ? '' : ' by $guard'}'
        '${overridable ? ', overridable' : ''}): ${r.whyNot}',
    _ => r.whyNot,
  }}',
);

/// Lets remote and the owner's own changes work through what was just done.
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 30));
