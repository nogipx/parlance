/// A house on parlance, start to end: its typed words, who may do what,
/// facts and the links they set off, a binding that holds a state, a guard
/// and a constraint, the user's own words, why a state is as it is, a phone
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

import 'house/house.dart';
import 'house/links.dart';
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
  // first words of its names, and that the doorbell says who rang (a fact
  // on a visitor's behalf). The owner's code never says what it may.
  final houseSide = registry.participant(
    Who.house,
    namespaces: {'light', 'heat', 'house', 'door', 'doorbell', 'motion'},
    rights: ParticipantRights(
      speakFor: (_, by, fact) => fact == HouseFact.rang.name
          ? null
          : 'only the doorbell speaks for anyone',
    ),
  );
  final owners = Owners(houseSide, [house]);
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

  // --- 7. A phone over remote ---------------------------------------------------

  section('A phone over remote');
  final phone = Phone.connect(registry, Who.phone('ann-phone'));
  final mirror = RegistryMirror()..follow(phone.client);
  final reply = await phone.client.command(HouseCommand.setHeat).callAt((
    target: 22,
  ), override: false);
  show('the phone sets the heating', reply.result);
  // The mirror shows what the call wrote once it has reached its seq.
  await mirror.reach(reply.epoch!, reply.seq!);
  print(
    '  the phone sees: ${mirror.state(HouseState.heat).read()} °C, '
    'mode ${mirror.state(HouseState.mode).read()?.name}',
  );
  final rings = await phone.client.fact(HouseFact.rang).recent(5);
  print('  rings it can see: ${[for (final f in rings) f.payload.who]}');
  await mirror.dispose();
  await phone.close();

  // --- 8. An agent over MCP --------------------------------------------------

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

/// A phone's connection: a session the house opens for it, and its client.
final class Phone {
  Phone._(this.client, this._session, this._closers);

  static Phone connect(Registry registry, Principal principal) {
    final (c, s) = RpcChannelTransport.memoryPair();
    // The host decides who the connection is, when it accepts it.
    final responder = RpcPeerEndpoint(transport: s);
    final session = RegistryResponder(
      responder,
      registry,
      principal: principal,
    );
    responder
      ..registerServiceContract(session)
      ..start();
    final caller = RpcPeerEndpoint(transport: c)..start();
    return Phone._(ParlanceClient(caller), session, [
      caller.close,
      responder.close,
    ]);
  }

  final ParlanceClient client;
  final RegistryResponder _session;
  final List<Future<void> Function()> _closers;

  Future<void> close() async {
    _session.close();
    for (final c in _closers) {
      await c();
    }
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
