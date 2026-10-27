/// Level 3, over the network: the phone is a participant too, across a
/// connection through rpc_dart. The host decides who the connection is
/// when it accepts it; the knob on the phone is the same class as in the
/// host's process.
///
/// Run: `dart run example/levels/level3_remote.dart`.
library;

import 'package:parlance/participant.dart';
import 'package:parlance/registry.dart';
import 'package:parlance/remote.dart';
import 'package:rpc_dart/rpc_dart.dart';

import 'player.dart';

Future<void> main() async {
  print('Level 3: over the network');
  final r = Registry();
  final player = startPlayer(r);

  // The host's end: a session that acts for the phone and nobody else.
  final (phoneEnd, hostEnd) = RpcChannelTransport.memoryPair();
  final host = RpcPeerEndpoint(transport: hostEnd);
  final session = r.participant(Who.phone).serve(host);
  host.start();

  // The phone's end: it joins over a connection. In memory one that does
  // not come back once lost; over a socket the factory would dial again,
  // and the phone would join again.
  final connection = RpcClientConnection(
    transportFactory: (_) async => phoneEnd,
    shouldReconnect: (_) => false,
  );
  final phone = await RemoteParticipant.join(connection);
  print('  the phone joined as ${phone.who}');

  // It keeps of another's state only what it watches.
  final volume = phone.state(PlayerState.volume);
  final watching = volume.watch().listen((_) {});
  final knob = Knob(
    volume: volume.reader(),
    setVolume: phone.command(PlayerCommand.setVolume).caller,
    clipped: phone.fact(PlayerFact.clipped).listener,
  );
  // A call answers once the phone's copy has what it wrote.
  await knob.turnTo(30);
  await knob.turnTo(96);
  await settle();
  print('  the host sees: ${r.state(PlayerState.volume).read()}');

  await watching.cancel();
  await phone.close();
  await connection.dispose();
  session.close();
  await host.close();
  player.dispose();
  await r.dispose();
}
