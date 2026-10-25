/// Level 3, over the network: a phone speaks the same words through
/// rpc_dart. The host decides who the connection is when it accepts it;
/// the phone reads through a mirror and calls through a client.
///
/// Run: `dart run example/levels/level3_remote.dart`.
library;

import 'package:parlance/registry.dart';
import 'package:parlance/remote.dart';
import 'package:rpc_dart/rpc_dart.dart';

import 'player.dart';

Future<void> main() async {
  print('Level 3: over the network');
  final r = Registry();
  definePlayer(r);

  // The host's end: a session that acts for the phone and nobody else.
  final (phoneEnd, hostEnd) = RpcChannelTransport.memoryPair();
  final host = RpcPeerEndpoint(transport: hostEnd);
  final session = RegistryResponder(host, r, principal: Who.phone);
  host
    ..registerServiceContract(session)
    ..start();

  // The phone's end: a client to call, a mirror to read.
  final phone = RpcPeerEndpoint(transport: phoneEnd)..start();
  final client = ParlanceClient(phone);
  final mirror = RegistryMirror()..follow(client);

  final reply = await client.command(PlayerCommand.setVolume).callAt((
    volume: 30,
  ));
  print('  the phone turns it to 30: ${reply.result.whyNot ?? 'done'}');
  // The mirror shows what the call wrote once it reached the call's seq.
  await mirror.reach(reply.epoch!, reply.seq!);
  print('  the phone sees: ${mirror.state(PlayerState.volume).read()}');
  print('  the host sees: ${r.state(PlayerState.volume).read()}');

  await mirror.dispose();
  session.close();
  await phone.close();
  await host.close();
  await r.dispose();
}
