/// A house on parlance, start to end: its typed words, who may do what and
/// whether a word is there for them, facts and the links they set off, a
/// binding that holds a state, a guard and a constraint, the user's own
/// words, a question that changes nothing, why a state is as it is and
/// which part did it, a device changed by hand, modules that say what they
/// need and a visit that comes and goes as a scope, a phone that joins
/// over remote and an agent over MCP.
///
/// Run: `dart run example/main.dart`.
library;

import 'dart:async';

import 'package:rpc_dart/rpc_dart.dart';
import 'package:parlance/links.dart';
import 'package:parlance/mcp.dart';
import 'package:parlance/owners.dart';
import 'package:parlance/participant.dart';
import 'package:parlance/registry.dart';
import 'package:parlance/remote.dart';
import 'package:parlance/view.dart';

import 'house/house.dart';
import 'house/links.dart';
import 'house/visit.dart';
import 'house/words.dart';

Future<void> main() async {
  // --- The registry, its owner, the links -----------------------------------

  final registry = Registry(
    overriders: Who.overriders,
    onError: (e, st) => print('error: $e'),
  );
  final devices = Devices();
  final house = House(devices);
  // The house speaks through a participant main makes: who it is, the
  // first words of its names, who calls its commands when a command does
  // not say (the household), and that the doorbell says who rang (a fact
  // on a visitor's behalf). The owner's code never says what it may.
  final houseSide = registry.participant(
    Who.house,
    namespaces: {'light', 'heat', 'house', 'door', 'doorbell', 'motion'},
    access: const WordAccess(call: Who.household),
    rights: ParticipantRights(
      speakFor: (_, by, fact) => fact == HouseFact.rang.name
          ? null
          : 'only the doorbell speaks for anyone',
    ),
  );
  // The owner is the participant's part `devices`, named here: what it
  // writes and says is told as house:devices.
  final owners = Owners(houseSide, {'devices': house});
  // Residents press and change links; a run set off by anyone else (a guest
  // at the door) acts with that one's rights, never the link's.
  final links = Links(
    registry,
    pressers: Who.residents,
    managers: Who.residents,
  );
  final problems = links.source('house', houseLinks);
  print('links taken: ${links.links.length}, problems: ${problems.length}');

  final setLight = registry.command(HouseCommand.setLight);
  final setHeat = registry.command(HouseCommand.setHeat);
  final setMode = registry.command(HouseCommand.setMode);
  final lock = registry.command(HouseCommand.lock);
  final light = registry.state(HouseState.light);
  final heat = registry.state(HouseState.heat);

  // --- 1. Typed calls, and who may make them --------------------------------

  section('Typed calls');
  // The params are the word's record: another command's do not compile.
  show(
    'ann turns the kitchen light on',
    await setLight.call((room: 'kitchen', on: true), by: Who.ann),
  );
  print('  kitchen light: ${light.read(key: 'kitchen')}');
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
    '  for bob: heat.set ${asBob.status(HouseCommand.setHeat.name)}, '
    'light.set ${asBob.status(HouseCommand.setLight.name)}, '
    'garage.open ${asBob.status('garage.open')}',
  );

  // --- 2. A fact sets off a reaction; why the state is so -------------------

  section('A fact and a reaction');
  house.motion('hall');
  await settle();
  print('  the hall light after motion: ${light.read(key: 'hall')}');
  final why = registry.explain(HouseState.light.name, key: 'hall');
  print(
    '  why: on behalf of ${why.change?.cause.by}, through ${why.change?.cause.chain}',
  );
  for (final c in why.trail) {
    print('    ${c.command} ${c.params} by ${c.cause.by}');
  }

  // --- 3. A binding holds a state while its condition is true ----------------

  section('A binding');
  await setMode.call((mode: Mode.night), by: Who.ann);
  await settle();
  print('  heating at night: ${heat.read()} °C');
  for (final l in registry.layers()) {
    print('    held by ${l.owner}: ${l.state} = ${l.value}');
  }
  await setMode.call((mode: Mode.home), by: Who.ann);
  await settle();
  print('  heating in the morning: ${heat.read()} °C');

  // --- 4. A guard of the house, and overriding it ---------------------------

  section('A guard');
  await setMode.call((mode: Mode.night), by: Who.ann);
  show('ann unlocks at night', await lock.call((on: false), by: Who.ann));
  show(
    'ann unlocks at night, overriding',
    await lock.call((on: false), by: Who.ann, override: true),
  );
  await lock.call((on: true), by: Who.ann);

  // --- 5. A constraint; a visitor sets off a temporary step ------------------

  section('Away');
  await setMode.call((mode: Mode.away), by: Who.ann);
  await settle();
  show(
    "ann's phone unlocks while away",
    await lock.call((on: false), by: Who.phone('ann-phone')),
  );
  final calls = <CallRecord>[];
  final listening = registry.calls.listen(calls.add);
  house.ring(Who.bob, 'bob');
  await settle();
  final porch = calls.firstWhere(
    (c) => c.command == HouseCommand.setLight.name,
  );
  print(
    '  bob rings: the porch light ${light.read(key: 'porch')}, '
    'called on behalf of ${porch.cause.by}',
  );
  await Future<void>.delayed(const Duration(milliseconds: 400));
  print('  a moment later: the porch light ${light.read(key: 'porch')}');
  await listening.cancel();
  await setMode.call((mode: Mode.home), by: Who.ann);

  // --- 6. The user's own words -------------------------------------------------

  section('Own words');
  // Own words are named at run time, by whoever writes the links: they are
  // called by name.
  show('ann calls my.movie', await registry.call('my.movie', {}, by: Who.ann));
  print(
    '  living ${light.read(key: 'living')}, '
    'kitchen ${light.read(key: 'kitchen')}',
  );
  show('bob calls my.movie', await registry.call('my.movie', {}, by: Who.bob));
  show(
    'ann sets my.guests',
    await registry.call('my.guests.set', {'value': true}, by: Who.ann),
  );
  print('  my.guests: ${registry.read('my.guests')}');

  // --- 7. A query: a question that changes nothing -----------------------------

  section('A query');
  // Asked, not called: it only answers, so asking again is safe, and the
  // registry keeps nothing of it (no call record, no id held).
  final rooms = registry.query(HouseQuery.rooms);
  final lit = await rooms.ask((lit: true), by: Who.bob);
  print('  rooms lit, asked by bob: ${(lit as CallDone<List<String>>).value}');
  final dark = await rooms.ask((lit: false), by: Who.bob);
  print('  and dark: ${(dark as CallDone<List<String>>).value}');
  final why2 = registry.explain(HouseState.light.name, key: 'living');
  print('  the living light was written by ${why2.change?.cause.by}');

  // --- 8. A switch flipped by hand ---------------------------------------------

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

  // --- 9. Modules beside the house: what they need, and a scope ---------------

  section('A visit, as a scope');
  // A garden that needs a weather station the house does not have: main
  // learns it at start, by name, rather than when it would water.
  final garden = Owners(
    registry.participant(Who.garden, namespaces: {'garden'}),
    {'sprinkler': Sprinkler()},
  );
  try {
    await garden.checkUses();
  } on UnmetUses catch (e) {
    print('  the garden cannot start: ${e.message}');
  }
  garden.dispose();
  // A visit is made when guests come and goes when they leave: its words
  // are there only meanwhile, and leave nothing behind.
  final visitSide = registry.participant(
    Who.visit,
    namespaces: {'visit'},
    access: const WordAccess(call: Who.household),
  );
  final visit = Owners(visitSide, {'book': Visit()});
  await visit.checkUses();
  final declared = registry.declarations[Who.visit.child('book')]!;
  print(
    '  the visit owns ${declared.owns.join(', ')}; uses '
    '${[for (final MapEntry(:key, :value) in declared.uses.entries) '$key (${value ? 'required' : 'optional'})'].join(', ')}',
  );
  house.ring(Who.bob, 'bob');
  await settle();
  final guests = registry.state(VisitState.guests);
  print('  guests: ${guests.read()}');
  visit.dispose();
  visitSide.dispose();
  print(
    '  after the visit: visit.guests ${asBob.status(VisitState.guests.name)}',
  );

  // --- 10. A phone that joins over remote ------------------------------------

  section('A phone over remote');
  // The phone is a participant like the house, across a connection: the
  // house opens a session for it and says who it is; it reads what it
  // watches.
  final phone = await Phone.join(registry, Who.phone('ann-phone'));
  final heats = phone.part.state(HouseState.heat).watch().listen((_) {});
  final modes = phone.part.state(HouseState.mode).watch().listen((_) {});
  final reply = await phone.part.command(HouseCommand.setHeat).call((
    target: 22,
  ));
  show('the phone sets the heating', reply);
  // A call answers once the phone's copy has what it wrote.
  print(
    '  the phone sees: ${phone.part.state(HouseState.heat).read()} °C, '
    'mode ${phone.part.state(HouseState.mode).read()?.name}',
  );
  final rings = await phone.part.fact(HouseFact.rang).recent(5);
  print('  rings it can see: ${[for (final f in rings) f.payload.who]}');
  await heats.cancel();
  await modes.cancel();
  await phone.close();

  // --- 11. An agent over MCP -------------------------------------------------

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

  await links.dispose();
  owners.dispose();
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

/// Lets links and remote work through what was just done.
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 30));
